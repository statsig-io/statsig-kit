import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

fileprivate final class MockNetworkMetadataProvider: StatsigNetworkMetadataProvider {
    private(set) var callCount = 0
    private let metadata: [String: String]

    init(metadata: [String: String]) {
        self.metadata = metadata
    }

    func getLogEventNetworkMetadata() -> [String: String] {
        callCount += 1
        return metadata
    }

    func shutdown() {}
}

class EventLoggerSpec: BaseSpec {
    private static func makeTaggedData(size: Int, marker: Int) -> Data {
        var data = withUnsafeBytes(of: UInt32(marker).bigEndian, Array.init)
        if size > data.count {
            data.append(contentsOf: repeatElement(UInt8(marker % 255), count: size - data.count))
        } else {
            data = Array(data.prefix(size))
        }
        return Data(data)
    }

    override func spec() {
        super.spec()

        describe("using EventLogger") {
            let sdkKey = "client-api-key"
            let loggerSDKKey = sdkKey
            let opts = StatsigOptions()
            var ns: NetworkService!
            let user = StatsigUser(userID: "jkw")
            let event1 = Event(
                user: user, name: "test_event1", value: 1, disableCurrentVCLogging: false)
            let event2 = Event(
                user: user, name: "test_event2", value: 2, disableCurrentVCLogging: false)
            let event3 = Event(
                user: user, name: "test_event3", value: "3", disableCurrentVCLogging: false)

            func makeNetworkService(options: StatsigOptions = opts) -> NetworkService {
                let store = InternalStore(sdkKey, StatsigUser(userID: "jkw"), options: options)
                return NetworkService(sdkKey: sdkKey, options: options, store: store)
            }

            beforeEach {
                TestUtils.clearStorage()
                ns = makeNetworkService()
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                EventLogger.deleteLocalStorage(sdkKey: sdkKey)
                TestUtils.clearStorage()
            }

            it("should add events to internal queue and send once flush timer hits") {

                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?
                stub(condition: isHost(LogEventHost)) { request in
                    actualRequest = request
                    actualRequestHttpBody =
                        try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let logger = EventLogger(
                    sdkKey: sdkKey, user: user, networkService: ns)
                logger.start(flushInterval: 1)
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)

                waitUntil(timeout: .seconds(2)) { done in
                    logger.logQueue.asyncAfter(deadline: .now() + 1) {
                        done()
                    }
                }

                expect(actualRequestHttpBody?.keys)
                    .toEventually(
                        contain("user", "events", "statsigMetadata"))
                expect((actualRequestHttpBody?["events"] as? [Any])?.count).toEventually(equal(3))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"])
                    .toEventually(
                        equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString)
                    .toEventually(
                        equal("https://prodregistryv2.org/v1/rgstr"))
            }

            it("should add events to internal queue and send once it passes max batch size") {
                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?

                stub(condition: isHost(LogEventHost)) { request in
                    actualRequest = request
                    actualRequestHttpBody =
                        try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let logger = EventLogger(
                    sdkKey: sdkKey, user: user, networkService: ns)
                logger.maxEventQueueSize = 3
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)

                expect(actualRequestHttpBody?.keys)
                    .toEventually(contain("user", "events", "statsigMetadata"))
                expect((actualRequestHttpBody?["events"] as? [Any])?.count).toEventually(equal(3))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"])
                    .toEventually(equal(sdkKey))
                expect(actualRequest?.httpMethod).toEventually(equal("POST"))
                expect(actualRequest?.url?.absoluteString)
                    .toEventually(
                        equal("https://prodregistryv2.org/v1/rgstr"))
            }

            it("should send events with flush()") {

                var actualRequest: URLRequest?
                var actualRequestHttpBody: [String: Any]?

                stub(condition: isHost(LogEventHost)) { request in
                    actualRequest = request
                    actualRequestHttpBody =
                        try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let logger = EventLogger(
                    sdkKey: sdkKey, user: user, networkService: ns)
                logger.start(flushInterval: 10)
                logger.maxEventQueueSize = 10
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)
                waitUntil { done in logger.flush(completion: done) }

                expect(actualRequestHttpBody?.keys).to(contain("user", "events", "statsigMetadata"))
                expect((actualRequestHttpBody?["events"] as? [Any])?.count).to(equal(3))
                expect(actualRequest?.allHTTPHeaderFields!["STATSIG-API-KEY"]).to(equal(sdkKey))
                expect(actualRequest?.httpMethod).to(equal("POST"))
                expect(actualRequest?.url?.absoluteString)
                    .to(equal("https://prodregistryv2.org/v1/rgstr"))
            }

            it(
                "should save failed to send requests locally during shutdown, and load and resend local requests during startup"
            ) {
                var isPendingRequest = true
                stub(condition: isHost(LogEventHost)) { request in
                    isPendingRequest = false
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 403, headers: nil)
                }

                let logger = EventLogger(sdkKey: loggerSDKKey, user: user, networkService: ns)
                logger.start(flushInterval: 10)
                logger.log(event1)
                logger.log(event2)
                logger.log(event3)
                logger.maxEventQueueSize = 10
                waitUntil { done in logger.stop(completion: done) }

                expect(isPendingRequest).toEventually(beFalse())
                expect(
                    readPersistedFailedRequests(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: loggerSDKKey
                    )
                )
                .toEventuallyNot(beEmpty())

                isPendingRequest = true

                let savedData =
                    readPersistedFailedRequests(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: loggerSDKKey
                    )
                    .map(\.body)
                var resendData: [Data] = []

                stub(condition: isHost(LogEventHost)) { request in
                    resendData.append(request.ohhttpStubs_httpBody!)
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 403, headers: nil)
                }

                let newLogger = EventLogger(
                    sdkKey: sdkKey, user: user, networkService: ns
                )
                // initialize calls retryFailedRequests
                newLogger.retryFailedRequests(forUser: user)

                expect(resendData.isEmpty).toEventually(beFalse())
                expect(savedData).toNot(beEmpty())
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
                        actualRequestHttpBody =
                            try! JSONSerialization.jsonObject(
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
                        client = StatsigClient(
                            sdkKey: "client-key", user: user,
                            options: StatsigOptions(disableDiagnostics: true),
                            completionWithResult: { _ in
                                done()
                            })
                    }

                    client?.logEvent(longEventName, value: 1)
                    client?.shutdown()

                    expect(actualRequestHttpBody?.keys)
                        .toEventually(contain("user", "events", "statsigMetadata"))
                    expect((actualRequestHttpBody?["events"] as? [[String: Any]])?.count)
                        .toEventually(beGreaterThanOrEqualTo(1))
                    let trimmedEventName = String(longEventName.prefix(64))
                    expect(
                        (actualRequestHttpBody?["events"] as? [[String: Any]])?
                            .map({ $0["eventName"] as? String })
                            .first(where: { $0 == trimmedEventName })
                    ).toEventuallyNot(beNil())
                }

                it(
                    "should send full event names if the disableEventNameTrimming option is set to true"
                ) {
                    waitUntil { done in
                        client = StatsigClient(
                            sdkKey: "client-key", user: user,
                            options: StatsigOptions(
                                disableDiagnostics: true, disableEventNameTrimming: true),
                            completionWithResult: { _ in
                                done()
                            })
                    }

                    client?.logEvent(longEventName, value: 1)
                    client?.shutdown()

                    expect(actualRequestHttpBody?.keys)
                        .toEventually(contain("user", "events", "statsigMetadata"))
                    expect((actualRequestHttpBody?["events"] as? [[String: Any]])?.count)
                        .toEventually(beGreaterThanOrEqualTo(1))
                    expect(
                        (actualRequestHttpBody?["events"] as? [[String: Any]])?
                            .map({ $0["eventName"] as? String })
                            .first(where: { $0 == longEventName })
                    ).toEventuallyNot(beNil())
                }
            }

            it("should drop oversized failed requests instead of persisting them") {
                var logEndpointCalled = false
                stub(condition: isHost(LogEventHost)) { req in
                    logEndpointCalled = true
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 500, headers: nil)
                }

                var text = ""
                for _ in 0...100000 {
                    text += "test1234567"
                }

                var logger = EventLogger(
                    sdkKey: sdkKey, user: user, networkService: ns
                )
                logger.start(flushInterval: 10)
                logger.log(
                    Event(
                        user: user, name: "a", value: 1, metadata: ["text": text],
                        disableCurrentVCLogging: false))
                waitUntil { done in logger.stop(completion: done) }

                // Fail to save because event is too big
                expect(logEndpointCalled).to(equal(true))
                expect(
                    decodeFailedLogRequestStore(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: sdkKey
                    )
                )
                .toEventuallyNot(beNil())
                expect(
                    readPersistedFailedRequests(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: sdkKey
                    ).count
                )
                .to(equal(0))
                expect(logger.failedRequestStore.pendingDroppedRequestSummary?.eventCount).to(
                    equal(1))

                logger = EventLogger(sdkKey: sdkKey, user: user, networkService: ns)
                logger.retryFailedRequests(forUser: user)
                logger.start(flushInterval: 2)
                logger.log(
                    Event(
                        user: user, name: "b", value: 1, metadata: ["text": "small"],
                        disableCurrentVCLogging: false))
                waitUntil { done in logger.stop(completion: done) }

                // Successfully save event
                expect(
                    decodeFailedLogRequestStore(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: sdkKey
                    )
                )
                .toEventuallyNot(beNil())
                expect(
                    readPersistedFailedRequests(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: sdkKey
                    ).count
                )
                .to(equal(1))
            }

            describe("with threads") {

                it("should save to disk from the main thread") {
                    stub(condition: isHost(LogEventHost)) { request in
                        return HTTPStubsResponse(
                            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                    }

                    let logger = EventLogger(
                        sdkKey: loggerSDKKey, user: user, networkService: ns)

                    expect(Thread.isMainThread).to(beTrue())

                    logger.failedRequestStore.addRequests(
                        from: [Data()],
                        lastFailedAtMs: 0,
                        requestEventCount: 0,
                        persist: false
                    )
                    logger.failedRequestStore.persist()

                    expect(
                        decodeFailedLogRequestStore(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        )
                    )
                    .toEventuallyNot(beNil())
                    expect(
                        readPersistedFailedRequests(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        ).count
                    )
                    .to(equal(1))
                }

                it("should save to disk from a background thread") {
                    let logger = EventLogger(
                        sdkKey: loggerSDKKey, user: user, networkService: ns)

                    DispatchQueue.global().async {
                        expect(Thread.isMainThread).to(beFalse())

                        logger.failedRequestStore.addRequests(
                            from: [Data()],
                            lastFailedAtMs: 0,
                            requestEventCount: 0,
                            persist: false
                        )
                        logger.failedRequestStore.persist()
                    }

                    expect(
                        decodeFailedLogRequestStore(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        )
                    )
                    .toEventuallyNot(beNil())
                    expect(
                        readPersistedFailedRequests(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        ).count
                    )
                    .to(equal(1))
                }

                it("should handle concurrent saves without deadlocks or corruption") {
                    let iterations = 1024
                    let numberOfTasks = 10

                    var queues: [DispatchQueue] = []
                    for i in 0..<numberOfTasks {
                        queues.append(DispatchQueue(label: "com.statsig.task_\(i)"))
                    }

                    let logger = EventLogger(
                        sdkKey: loggerSDKKey, user: user, networkService: ns)

                    var i = 0

                    for j in 0..<iterations {
                        let queue = queues[j % numberOfTasks]

                        queue.async {
                            logger.failedRequestStore.addRequests(
                                from: [Data([UInt8(j % 256)])],
                                lastFailedAtMs: 0,
                                requestEventCount: 0,
                                persist: false
                            )
                            logger.failedRequestStore.persist()
                            i += 1
                        }
                    }

                    expect(i).toEventually(equal(iterations), timeout: .seconds(5))
                    expect(
                        decodeFailedLogRequestStore(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        )
                    )
                    .toEventuallyNot(beNil())
                    expect(
                        readPersistedFailedRequests(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        ).count
                    )
                    .to(equal(iterations))

                    var counters = Array(repeating: UInt8(0), count: 256)

                    let requests = readPersistedFailedRequests(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: loggerSDKKey
                    ).map(\.body)

                    for req in requests {
                        if let firstByte = req.first {
                            counters[Int(firstByte)] += 1
                        }
                    }

                    for count in counters {
                        expect(count).to(equal(4))
                    }
                }

                it("should not save to disk while addFailedLogRequest is running") {
                    let numberOfRequest = 250
                    let requestSize = 4000

                    let addQueue = DispatchQueue(
                        label: "com.statsig.add_failed_requests", qos: .userInitiated,
                        attributes: .concurrent)
                    let saveQueue = DispatchQueue(
                        label: "com.statsig.save_failed_requests", qos: .userInitiated,
                        attributes: .concurrent)

                    let logger = EventLogger(
                        sdkKey: loggerSDKKey, user: user, networkService: ns)
                    logger.retryFailedRequests(forUser: user)

                    saveQueue.async {
                        // Wait for the addFailedLogRequest to start adding requests to the queue
                        while logger.failedRequestStore.requests.count == 0 {
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        while logger.failedRequestStore.lock.try() {
                            logger.failedRequestStore.lock.unlock()
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                        // Once we fail to get the lock, try saving to disk
                        logger.failedRequestStore.persist()
                    }

                    addQueue.async {
                        // Continuously add requests to ensure we have the lock
                        while decodeFailedLogRequestStore(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        ) == nil {
                            let requests = (0..<numberOfRequest).map { index in
                                Self.makeTaggedData(size: requestSize, marker: index)
                            }
                            logger.failedRequestStore.addRequests(
                                from: requests,
                                lastFailedAtMs: 0,
                                requestEventCount: 0,
                                persist: false
                            )
                            // Test that the queue is not empty
                            expect(logger.failedRequestStore.requests.count).to(beGreaterThan(0))
                            let totalBodyBytes = logger.failedRequestStore.requests.reduce(0) {
                                $0 + $1.body.count
                            }
                            expect(totalBodyBytes).to(
                                beLessThanOrEqualTo(
                                    FailedLogRequestStore.defaultMaxStoreSizeBytes))
                            Thread.sleep(forTimeInterval: 0.001)
                        }
                    }

                    expect(
                        decodeFailedLogRequestStore(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        )
                    )
                    .toEventuallyNot(beNil(), timeout: .seconds(5))
                    expect(
                        readPersistedFailedRequests(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: loggerSDKKey
                        ).count
                    )
                    .to(beGreaterThan(0))
                }
            }

            describe("dropped request summary") {
                var logger: EventLogger!

                beforeEach {
                    logger = EventLogger(sdkKey: loggerSDKKey, user: user, networkService: ns)
                }

                it("flushes dropped request summaries as a count event") {
                    var requestEvents: [[String: Any]]?
                    stub(condition: isHost(LogEventHost)) { request in
                        let requestBody =
                            try! JSONSerialization.jsonObject(
                                with: request.ohhttpStubs_httpBody!,
                                options: []) as! [String: Any]
                        requestEvents = requestBody["events"] as? [[String: Any]]
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    logger.failedRequestStore.addRequests([
                        FailedLogRequest(
                            body: Data(
                                count: FailedLogRequestStore.defaultMaxStoreSizeBytes + 100),
                            lastFailedAtMs: 456,
                            requestEventCount: 9
                        )
                    ])
                    logger.failedRequestStore.persist()

                    waitUntil { done in logger.flush(completion: done) }

                    let droppedEvent = requestEvents?.first {
                        $0["eventName"] as? String == "dropped_log_event.count"
                    }

                    expect(droppedEvent).toNot(beNil())
                    expect((droppedEvent?["value"] as? NSNumber)?.doubleValue).to(equal(9))
                    expect(Time.parse(droppedEvent?["time"])).to(equal(456))
                    expect(droppedEvent?["metadata"]).to(beNil())
                }

                it(
                    "restores pending dropped request summaries and accounts for current events when encoding fails"
                ) {
                    logger.failedRequestStore.restorePendingDroppedRequestSummary(
                        DroppedLogRequestSummary(eventCount: 9, lastFailedAtMs: 456)
                    )
                    logger.log(
                        Event(
                            user: user,
                            name: "bad_event",
                            value: Date(),
                            disableCurrentVCLogging: true
                        ))

                    waitUntil { done in logger.flush(completion: done) }

                    expect(logger.failedRequestStore.requests).to(beEmpty())
                    expect(logger.failedRequestStore.pendingDroppedRequestSummary?.eventCount).to(
                        equal(10))
                    expect(logger.failedRequestStore.pendingDroppedRequestSummary?.lastFailedAtMs)
                        .to(beGreaterThanOrEqualTo(456))
                }

                it("counts pending dropped request summaries when persisting a new failed request")
                {
                    let disabledOptions = StatsigOptions(eventLoggingEnabled: false)
                    let disabledNetworkService = makeNetworkService(options: disabledOptions)
                    logger = EventLogger(
                        sdkKey: loggerSDKKey,
                        user: user,
                        networkService: disabledNetworkService
                    )
                    logger.failedRequestStore.restorePendingDroppedRequestSummary(
                        DroppedLogRequestSummary(eventCount: 9, lastFailedAtMs: 456)
                    )
                    logger.log(
                        Event(
                            user: user,
                            name: "new_event",
                            disableCurrentVCLogging: true
                        ))

                    waitUntil { done in logger.flush(completion: done) }

                    expect(logger.failedRequestStore.requests).to(haveCount(1))
                    expect(logger.failedRequestStore.requests.first?.requestEventCount).to(
                        equal(10))
                    expect(logger.failedRequestStore.pendingDroppedRequestSummary).to(beNil())
                }
            }

            describe("with pending events") {
                var logger: EventLogger!

                func readRetryQueue() -> [Data] {
                    return readPersistedFailedRequests(
                        storageAdapter: logger.failedRequestStore.storageAdapter,
                        sdkKey: loggerSDKKey
                    ).map(\.body)
                }

                func flushAndWait(persistPendingEvents: Bool = false) {
                    waitUntil { done in
                        logger.flush(persistPendingEvents: persistPendingEvents) {
                            DispatchQueue.main.async {
                                done()
                            }
                        }
                    }
                }

                beforeEach {
                    logger = EventLogger(sdkKey: loggerSDKKey, user: user, networkService: ns)
                }

                afterEach {
                    logger.stop()
                    logger = EventLogger(sdkKey: loggerSDKKey, user: user, networkService: ns)
                }

                it("should persist pending events while the request is in progress") {
                    var dataDuringRequest: [Data]?

                    stub(condition: isHost(LogEventHost)) { request in
                        let timeout = Date().addingTimeInterval(0.5)
                        repeat {
                            dataDuringRequest = readRetryQueue()
                            if dataDuringRequest?.isEmpty == false {
                                break
                            }
                            Thread.sleep(forTimeInterval: 0.001)
                        } while Date() < timeout

                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    logger.log(event1)

                    // Ensures the the retry queue starts empty
                    expect(readRetryQueue()).to(beEmpty())

                    flushAndWait(persistPendingEvents: true)

                    expect(dataDuringRequest).toNot(beEmpty())
                }

                it("should not contain pending events after a successful request") {
                    stub(condition: isHost(LogEventHost)) { request in
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    logger.log(event1)

                    // Ensures the the retry queue starts empty
                    expect(readRetryQueue()).to(beEmpty())

                    flushAndWait(persistPendingEvents: true)

                    let dataAfterRequest = readRetryQueue()
                    expect(dataAfterRequest).to(beEmpty())
                }

                it("should contain pending events after a failed request") {
                    stub(condition: isHost(LogEventHost)) { request in
                        return HTTPStubsResponse(
                            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                    }

                    logger.log(event1)

                    // Ensures the the retry queue starts empty
                    expect(readRetryQueue()).to(beEmpty())

                    flushAndWait(persistPendingEvents: true)

                    let dataAfterRequest = readRetryQueue()
                    expect(dataAfterRequest).toNot(beEmpty())
                }

                it("should keep existing items in the failed request queue") {
                    var dataDuringRequest: [Data]?

                    // Add something to the retry queue
                    let mockFailedRequests = [Data(count: 16), Data(count: 12), Data(count: 24)]
                    logger.failedRequestStore.addRequests(
                        from: mockFailedRequests,
                        lastFailedAtMs: 0,
                        requestEventCount: 0,
                        persist: false
                    )
                    logger.failedRequestStore.persist()

                    stub(condition: isHost(LogEventHost)) { request in
                        let expectedCount = mockFailedRequests.count + 1
                        let timeout = Date().addingTimeInterval(0.5)
                        repeat {
                            dataDuringRequest = readRetryQueue()
                            if dataDuringRequest?.count == expectedCount {
                                break
                            }
                            Thread.sleep(forTimeInterval: 0.001)
                        } while Date() < timeout

                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    logger.log(event1)

                    flushAndWait(persistPendingEvents: true)

                    expect(dataDuringRequest).to(haveCount(mockFailedRequests.count + 1))

                    let dataAfterRequest = readRetryQueue()

                    expect(dataAfterRequest).to(equal(mockFailedRequests))
                }

                it(
                    "should not persist pending events when persistPendingEvents is false and request succeeds"
                ) {
                    var dataDuringRequest: [Data]?

                    stub(condition: isHost(LogEventHost)) { request in
                        dataDuringRequest = readRetryQueue()
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    logger.log(event1)

                    // Ensures the retry queue starts empty
                    expect(readRetryQueue()).to(beEmpty())

                    flushAndWait(persistPendingEvents: false)

                    expect(dataDuringRequest).to(beEmpty())
                    expect(readRetryQueue()).to(beEmpty())
                }
            }

            describe("log network metadata") {
                var client: StatsigClient?

                beforeEach {
                    stub(condition: isHost(ApiHost) && isPath("/v1/initialize")) { _ in
                        HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                    stub(condition: isHost(LogEventHost)) { _ in
                        HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                }

                afterEach {
                    client?.shutdown()
                    client = nil
                }

                it("adds network metadata to events when enabled") {
                    let provider = MockNetworkMetadataProvider(
                        metadata: ["netType": "wifi", "hasInternet": "true"])

                    waitUntil { done in
                        client = StatsigClient(
                            sdkKey: "client-key",
                            user: user,
                            options: StatsigOptions(
                                logNetworkMetadata: true,
                                disableDiagnostics: true),
                            completionWithResult: { _ in
                                done()
                            })
                    }

                    expect(client?.networkMetadataProvider is StatsigEnabledNetworkMetadataProvider)
                        .to(beTrue())

                    client?.networkMetadataProvider = provider
                    client?.logEvent("network_event")

                    waitUntil { done in
                        client?.logger.logQueue.async {
                            done()
                        }
                    }

                    let networkEvent = client?.logger.events.first(where: { event in
                        event.name == "network_event"
                    })

                    expect(networkEvent?.statsigMetadata).to(
                        equal([
                            "netType": "wifi",
                            "hasInternet": "true",
                        ]))
                    expect(provider.callCount).to(equal(1))
                }

                it("does not add network metadata to events when disabled") {
                    let provider = MockNetworkMetadataProvider(
                        metadata: ["netType": "wifi", "hasInternet": "true"])

                    waitUntil { done in
                        client = StatsigClient(
                            sdkKey: "client-key",
                            user: user,
                            options: StatsigOptions(
                                logNetworkMetadata: false,
                                disableDiagnostics: true),
                            completionWithResult: { _ in
                                done()
                            })
                    }

                    expect(client?.networkMetadataProvider is StatsigNoOpNetworkMetadataProvider)
                        .to(beTrue())

                    client?.networkMetadataProvider = provider
                    client?.logEvent("network_event")

                    waitUntil { done in
                        client?.logger.logQueue.async {
                            done()
                        }
                    }

                    let networkEvent = client?.logger.events.first(where: { event in
                        event.name == "network_event"
                    })

                    expect(networkEvent?.statsigMetadata).to(beNil())
                    expect(provider.callCount).to(equal(0))
                }

                it("does not add empty network metadata to events when enabled") {
                    let provider = MockNetworkMetadataProvider(metadata: [:])

                    waitUntil { done in
                        client = StatsigClient(
                            sdkKey: "client-key",
                            user: user,
                            options: StatsigOptions(
                                logNetworkMetadata: true,
                                disableDiagnostics: true),
                            completionWithResult: { _ in
                                done()
                            })
                    }

                    client?.networkMetadataProvider = provider
                    client?.logEvent("network_event")

                    waitUntil { done in
                        client?.logger.logQueue.async {
                            done()
                        }
                    }

                    let networkEvent = client?.logger.events.first(where: { event in
                        event.name == "network_event"
                    })

                    expect(networkEvent?.statsigMetadata).to(beNil())
                    expect(provider.callCount).to(equal(1))
                }
            }
        }
    }
}
