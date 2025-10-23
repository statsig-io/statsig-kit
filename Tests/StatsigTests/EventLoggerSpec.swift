import Foundation

import Nimble
import OHHTTPStubs
import Quick

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

@testable import Statsig

class EventLoggerSpec: BaseSpec {

    override func spec() {
        super.spec()
        
        describe("using EventLogger") {
            let sdkKey = "client-api-key"
            let opts = StatsigOptions()
            
            let store = InternalStore(sdkKey, StatsigUser(userID: "jkw"), options: opts)
            
            let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)
            let user = StatsigUser(userID: "jkw")
            let event1 = Event(user: user, name: "test_event1", value: 1, disableCurrentVCLogging: false)
            let event2 = Event(user: user, name: "test_event2", value: 2, disableCurrentVCLogging: false)
            let event3 = Event(user: user, name: "test_event3", value: "3", disableCurrentVCLogging: false)
            afterEach {
                HTTPStubs.removeAllStubs()
                EventLogger.deleteLocalStorage(sdkKey: "client-key")
            }

            it("should add events to internal queue and send once flush timer hits") {

                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?
                stub(condition: isHost(LogEventHost)) { request in
                    actualRequest = request
                    actualRequestHttpBody = try! JSONSerialization.jsonObject(
                        with: request.ohhttpStubs_httpBody!,
                        options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: MockDefaults())
                logger.start(flushInterval: 1)
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)

                waitUntil(timeout: .seconds(2)) { done in
                    logger.logQueue.asyncAfter(deadline: .now() + 1) {
                        done()
                    }
                }

                expect(actualRequestHttpBody?.keys).toEventually(contain("user", "events", "statsigMetadata"))
                expect((actualRequestHttpBody?["events"] as? [Any])?.count).toEventually(equal(3))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString).toEventually(equal("https://prodregistryv2.org/v1/rgstr"))
            }

            it("should add events to internal queue and send once it passes max batch size") {
                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?

                stub(condition: isHost(LogEventHost)) { request in
                    actualRequest = request
                    actualRequestHttpBody = try! JSONSerialization.jsonObject(
                        with: request.ohhttpStubs_httpBody!,
                        options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: MockDefaults())
                logger.maxEventQueueSize = 3
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)

                expect(actualRequestHttpBody?.keys).toEventually(contain("user", "events", "statsigMetadata"))
                expect((actualRequestHttpBody?["events"] as? [Any])?.count).toEventually(equal(3))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString).toEventually(equal("https://prodregistryv2.org/v1/rgstr"))
            }

            it("should send events with flush()") {

                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?

                stub(condition: isHost(LogEventHost)) { request in
                    actualRequest = request
                    actualRequestHttpBody = try! JSONSerialization.jsonObject(
                        with: request.ohhttpStubs_httpBody!,
                        options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: MockDefaults())
                logger.start(flushInterval: 10)
                logger.maxEventQueueSize = 10
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)
                logger.flush()

                expect(actualRequestHttpBody?.keys).toEventually(contain("user", "events", "statsigMetadata"))
                expect((actualRequestHttpBody?["events"] as? [Any])?.count).toEventually(equal(3))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString).toEventually(equal("https://prodregistryv2.org/v1/rgstr"))
            }

            it("should save failed to send requests locally during shutdown, and load and resend local requests during startup") {
                var isPendingRequest = true
                stub(condition: isHost(LogEventHost)) { request in
                    isPendingRequest = false
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 403, headers: nil)
                }

                let userDefaults = MockDefaults()
                let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)
                logger.start(flushInterval: 10)
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)
                logger.maxEventQueueSize = 10
                logger.stop()

                expect(isPendingRequest).toEventually(beFalse())
                expect(userDefaults.data[getFailedEventStorageKey("client-key")] as? [Data]).toEventuallyNot(beNil())

                isPendingRequest = true

                let savedData = userDefaults.data[getFailedEventStorageKey("client-key")] as? [Data]
                var resendData: [Data] = []

                stub(condition: isHost(LogEventHost)) { request in
                    resendData.append(request.ohhttpStubs_httpBody!)
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 403, headers: nil)
                }

                let newLogger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)
                // initialize calls retryFailedRequests
                newLogger.retryFailedRequests(forUser: user)

                expect(resendData.isEmpty).toEventually(beFalse())
                expect(savedData).toEventuallyNot(beNil())
                expect(savedData).toEventually(equal(resendData))
            }

            // NOTE: This behavior should be removed with the next major release
            describe("trimming event names") {
                let longEventName = String(repeating: "1234567890", count: 10)

                var actualRequestHttpBody: [String: Any]?
                var client: StatsigClient?
                beforeEach {
                    // Prevent calls to initialize
                    stub(condition: isHost(ApiHost) && isPath("/v1/initialize")) { req in
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                    stub(condition: isHost(LogEventHost)) { request in
                        actualRequestHttpBody = try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                }

                afterEach {
                    client = nil
                    actualRequestHttpBody = nil
                }

                it("should trim event names to 64 characters") {

                    waitUntil { done in
                        client = StatsigClient(sdkKey: "client-key", user: user, options: StatsigOptions(disableDiagnostics: true), completionWithResult: { _ in
                            done()
                        })
                    }

                    client?.logEvent(longEventName, value: 1)
                    client?.shutdown()

                    expect(actualRequestHttpBody?.keys).toEventually(contain("user", "events", "statsigMetadata"))
                    expect((actualRequestHttpBody?["events"] as? [[String: Any]])?.count).toEventually(beGreaterThanOrEqualTo(1))
                    let trimmedEventName = String(longEventName.prefix(64))
                    expect((actualRequestHttpBody?["events"] as? [[String: Any]])?
                        .map({ $0["eventName"] as? String })
                        .first(where: { $0 == trimmedEventName })).toEventuallyNot(beNil())
                }

                it("should send full event names if the disableEventNameTrimming option is set to true") {
                    waitUntil { done in
                        client = StatsigClient(sdkKey: "client-key", user: user, options: StatsigOptions(disableDiagnostics: true, disableEventNameTrimming: true), completionWithResult: { _ in
                            done()
                        })
                    }

                    client?.logEvent(longEventName, value: 1)
                    client?.shutdown()

                    expect(actualRequestHttpBody?.keys).toEventually(contain("user", "events", "statsigMetadata"))
                    expect((actualRequestHttpBody?["events"] as? [[String: Any]])?.count).toEventually(beGreaterThanOrEqualTo(1))
                    expect((actualRequestHttpBody?["events"] as? [[String: Any]])?
                        .map({ $0["eventName"] as? String })
                        .first(where: { $0 == longEventName })).toEventuallyNot(beNil())
                }
            }

            it("should limit file size save to user defaults") {
                var logEndpointCalled = false
                stub(condition: isHost(LogEventHost)) { req in
                    logEndpointCalled = true
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 500, headers: nil)
                }

                let userDefaults = MockDefaults()

                var text = ""
                for _ in 0...100000 {
                    text += "test1234567"
                }

                var logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)
                logger.start(flushInterval: 10)
                logger.log(Event(user: user, name: "a", value: 1, metadata: ["text": text], disableCurrentVCLogging: false))
                logger.stop()
                let failedEventsStorageKey = logger.storageKey

                // Fail to save because event is too big
                expect(logEndpointCalled).toEventually(equal(true))
                expect(userDefaults.data[failedEventsStorageKey] as? [Data]).toEventuallyNot(beNil())
                expect((userDefaults.data[failedEventsStorageKey] as! [Data]).count).to(equal(0))

                userDefaults.reset()

                logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)
                logger.retryFailedRequests(forUser: user)
                logger.start(flushInterval: 2)
                logger.log(Event(user: user, name: "b", value: 1, metadata: ["text": "small"], disableCurrentVCLogging: false))
                logger.stop()

                // Successfully save event
                expect(userDefaults.data[failedEventsStorageKey] as? [Data]).toEventuallyNot(beNil())
                expect((userDefaults.data[failedEventsStorageKey] as? [Data])?.count).to(equal(1))
            }

            describe("with threads") {

                it("should save to disk from the main thread") {
                    stub(condition: isHost(LogEventHost)) { request in
                        return HTTPStubsResponse(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                    }
                    
                    let userDefaults = MockDefaults()
                    let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)

                    expect(Thread.isMainThread).to(beTrue())

                    logger.addFailedLogRequest([Data()])
                    logger.saveFailedLogRequestsToDisk()
                    
                    expect(userDefaults.array(forKey: logger.storageKey)).toEventuallyNot(beNil())
                    expect(userDefaults.array(forKey: logger.storageKey)?.count).to(equal(1))
                }

                it("should save to disk from a background thread") {
                    let userDefaults = MockDefaults()
                    let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)
                    
                    DispatchQueue.global().async {
                        expect(Thread.isMainThread).to(beFalse())

                        logger.addFailedLogRequest([Data()])
                        logger.saveFailedLogRequestsToDisk()
                    }

                    expect(userDefaults.array(forKey: logger.storageKey)).toEventuallyNot(beNil())
                    expect(userDefaults.array(forKey: logger.storageKey)?.count).to(equal(1))
                }


                it("should handle concurrent saves without deadlocks or corruption") {
                    let iterations = 1024
                    let numberOfTasks = 10

                    var queues: [DispatchQueue] = []
                    for i in 0..<numberOfTasks {
                        queues.append(DispatchQueue(label: "com.statsig.task_\(i)"))
                    }

                    let userDefaults = MockDefaults()
                    let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)

                    var i = 0

                    for j in 0..<iterations {
                        let queue = queues[j % numberOfTasks]

                        queue.async {
                            logger.addFailedLogRequest([Data([UInt8(j % 256)])])
                            logger.saveFailedLogRequestsToDisk()
                            i += 1
                        }
                    }

                    expect(i).toEventually(equal(iterations), timeout: .seconds(5))
                    expect(userDefaults.array(forKey: logger.storageKey)).toEventuallyNot(beNil())
                    expect(userDefaults.array(forKey: logger.storageKey)?.count).to(equal(iterations))

                    var counters = Array(repeating: UInt8(0), count: 256)

                    let requests = userDefaults.array(forKey: logger.storageKey) as? [Data]

                    for req in requests ?? [] {
                        if let firstByte = req.first {
                            counters[Int(firstByte)] += 1
                        }
                    }

                    for count in counters {
                        expect(count).to(equal(4))
                    }
                }

                it("should not save to disk while addFailedLogRequest is running") {
                    let numberOfRequest = 1005
                    let requestSize = 1000

                    let addQueue = DispatchQueue(label: "com.statsig.add_failed_requests", qos: .userInitiated, attributes: .concurrent)
                    let saveQueue = DispatchQueue(label: "com.statsig.save_failed_requests", qos: .userInitiated, attributes: .concurrent)

                    let userDefaults = MockDefaults()
                    let logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: userDefaults)
                    logger.retryFailedRequests(forUser: user)

                    saveQueue.async {
                        // Wait for the addFailedLogRequest to start adding requests to the queue
                        while (logger.failedRequestQueue.count == 0) {
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        while logger.failedRequestLock.try() {
                            logger.failedRequestLock.unlock()
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        // Once we fail to get the lock, try saving to disk
                        logger.saveFailedLogRequestsToDisk()
                    }

                    addQueue.async {
                        // Continuously add requests to ensure we have the lock
                        while (userDefaults.array(forKey: logger.storageKey) == nil) {
                            let requests = (0..<numberOfRequest).map { _ in Data(repeating: 0, count: requestSize) }
                            logger.addFailedLogRequest(requests)
                            // Test that the queue is not empty
                            expect(logger.failedRequestQueue.count).to(beGreaterThan(0))
                            // Test that the requests didn't fit the queue
                            expect(logger.failedRequestQueue.count).to(beLessThan(numberOfRequest))
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                    }

                    expect(userDefaults.array(forKey: logger.storageKey)).toEventuallyNot(beNil())
                    expect(userDefaults.array(forKey: logger.storageKey)?.count).to(beGreaterThan(0))
                }
            }

            describe("addFailedLogRequest") {
                var logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: MockDefaults())
                let limit = logger.MAX_SAVED_LOG_REQUEST_SIZE;

                let bigdata = Data(count: limit + 100)
                let mediumdata = Data(count: limit / 2 + 100)
                let smalldata = Data(count: 100)
                

                beforeEach {
                    logger = EventLogger(sdkKey: "client-key", user: user, networkService: ns, userDefaults: MockDefaults())
                }

                it("accepts data under the limit") {
                    logger.addFailedLogRequest([smalldata, smalldata, smalldata])
                    expect(logger.failedRequestQueue.count).to(equal(3))
                }
                it("clears first queue items until it reaches the limit") {
                    logger.addFailedLogRequest([smalldata, smalldata, smalldata])
                    logger.addFailedLogRequest([mediumdata])
                    logger.addFailedLogRequest([smalldata, smalldata, smalldata, mediumdata])
                    expect(logger.failedRequestQueue.count).to(equal(4))
                }
                it("can clear the first item of the queue") {
                    logger.addFailedLogRequest([mediumdata])
                    logger.addFailedLogRequest([smalldata, smalldata, smalldata, mediumdata])
                    expect(logger.failedRequestQueue.count).to(equal(4))
                }
                it("can keep the last item of the queue") {
                    logger.addFailedLogRequest([mediumdata, smalldata, smalldata])
                    logger.addFailedLogRequest([mediumdata, mediumdata])
                    expect(logger.failedRequestQueue.count).to(equal(1))
                }
                it("keeps part of the data array if it's above the limit") {
                    logger.addFailedLogRequest([smalldata, mediumdata, smalldata, smalldata, smalldata, mediumdata])
                    expect(logger.failedRequestQueue.count).to(equal(4))
                }
                it("clears the entire queue if the last item is above the limit") {
                    logger.addFailedLogRequest([smalldata, smalldata, smalldata])
                    logger.addFailedLogRequest([mediumdata])
                    logger.addFailedLogRequest([bigdata])
                    expect(logger.failedRequestQueue.count).to(equal(0))
                }
            }
        }
    }
}
