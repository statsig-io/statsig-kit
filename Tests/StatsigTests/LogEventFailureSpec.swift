import Foundation

import Nimble
import OHHTTPStubs
import Quick
@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class MockNetwork: NetworkService {
    var responseError: String?
    var responseData: Data?
    var response: URLResponse?
    var responseIsAsync = false
    var timesCalled: Int = 0

    init() {
        let opts = StatsigOptions()
        let store = InternalStore("", StatsigUser(), options: opts)
        super.init(sdkKey: "", options: opts, store: store)
    }

    override func sendEvents(
        forUser: StatsigUser,
        events: [Event],
        completion: @escaping ((String?, Data?) -> Void)) {
            let work = { [weak self] in
                guard let it = self else { return }
                completion(it.responseError, it.responseData)
                it.timesCalled += 1
            }

            responseIsAsync ? DispatchQueue.global().async(execute: work) : work()
    }
}

class LogEventFailureSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("LogEventFailure") {
            let sdkKey = "client-key"
            let user = StatsigUser(userID: "a-user")
            let defaults = MockDefaults()

            var logger: EventLogger!

            describe("threads") {
                var network: MockNetwork!

                beforeEach {
                    defaults.data.reset([:])

                    network = MockNetwork()
                    network.responseError = "Nah uh uh uh"
                    network.responseData = "{}".data(using: .utf8)

                    logger = EventLogger(sdkKey: sdkKey, user: user, networkService: network, userDefaults: defaults)
                    logger.log(Event(user: user, name: "an_event", disableCurrentVCLogging: true))
                }

                it("handles errors that come back on the calling thread") {
                    network.responseIsAsync = false
                    waitUntil { done in logger.flush(completion: done) }
                    expect(network.timesCalled).to(equal(1))
                    expect(logger.failedRequestQueue.count).to(equal(1))
                }

                it("handles errors that come back on a bg thread") {
                    network.responseIsAsync = true
                    waitUntil { done in logger.flush(completion: done) }
                    expect(network.timesCalled).to(equal(1))
                    expect(logger.failedRequestQueue.count).to(equal(1))
                }
            }

            describe("queue management") {
                let opts = StatsigOptions()
                let store = InternalStore(sdkKey, user, options: opts)
                let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)

                var requestCount = 0
                var originalEventRetryCount = 0
                var lastRequest: URLRequest? = nil

                func createLogger() {
                    logger = EventLogger(sdkKey: sdkKey, user: user, networkService: ns, userDefaults: defaults)
                    logger.retryFailedRequests(forUser: user)
                }

                beforeEach {
                    lastRequest = nil
                    NetworkService.disableCompression = false
                    defaults.data.reset([:])
                    requestCount = 0
                    originalEventRetryCount = 0

                    stubError()
                    createLogger()

                    logger.log(Event(user: user, name: "an_event", disableCurrentVCLogging: true))
                }

                func teardownNetwork() {
                    HTTPStubs.removeAllStubs()
                    requestCount = 0
                    originalEventRetryCount = 0
                }

                afterEach {
                    teardownNetwork()
                    NetworkService.disableCompression = true
                }

                func stubError() {
                    stub(condition: isHost(LogEventHost)) { request in
                        requestCount += 1;
                        lastRequest = request;
                        // Use a cancelled error to prevent the network retry logic
                        return HTTPStubsResponse(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                    }
                }

                func stubOK() {
                    stub(condition: isHost(LogEventHost)) { request in
                        requestCount += 1;
                        lastRequest = request;
                        if let events = request.statsig_body?["events"] as? [[String: Any]] {
                            originalEventRetryCount += events.filter({ $0["eventName"] as? String == "an_event" }).count
                        }
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                }

                it("an event failed multiple times isn't duplicated in the queue") {
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestQueue).toNot(beEmpty())
                    
                    // Shutdown the current logger. Create a new one.
                    waitUntil { done in logger.stop(completion: done) }
                    createLogger()

                    expect(logger.failedRequestQueue).toEventuallyNot(beEmpty())

                    // Check if the initial event isn't duplicated in the queue
                    var initialEventQueued = 0
                    for requestBody in logger.failedRequestQueue {
                        // Decode events from saved body
                        guard
                            let body = try? JSONSerialization.jsonObject(
                                with: requestBody,
                                options: []) as? [String: Any],
                            let events = body["events"] as? [[String: Any]]
                        else {
                            continue
                        }
                        // Check if body is the initial event
                        for event in events {
                            if (event["eventName"] as? String == "an_event") {
                                initialEventQueued += 1
                            }
                        }
                    }
                    expect(initialEventQueued).to(equal(1))
                }

                it("persists failed events across SDK initializations") {
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestQueue.count).to(equal(1)) // Initial event + new event
                    
                    // Shutdown the current logger
                    waitUntil { done in logger.stop(completion: done) }
                    
                    // Verify events were persisted to UserDefaults
                    let storageKey = logger.storageKey
                    expect(defaults.array(forKey: storageKey)).toNot(beNil())
                    expect(defaults.array(forKey: storageKey)).toNot(beEmpty())
                    
                    teardownNetwork()
                    stubError()
                    createLogger()

                    expect(requestCount).toEventually(beGreaterThanOrEqualTo(1))
                    expect(logger.failedRequestQueue).toEventuallyNot(beNil())
                    expect(logger.failedRequestQueue).toEventuallyNot(beEmpty())
                }
                
                it("retries failed requests on next initialization") {
                    waitUntil { done in logger.stop(completion: done) }
                    expect(requestCount).to(equal(1))
                    expect(logger.failedRequestQueue.count).to(equal(1))
                    expect(defaults.array(forKey: logger.storageKey)).toEventuallyNot(beNil())
                    expect(defaults.array(forKey: logger.storageKey)).toEventuallyNot(beEmpty())
                    
                    teardownNetwork()
                    stubOK()
                    createLogger()

                    expect(requestCount).toEventually(equal(1))
                    expect(logger.failedRequestQueue.count).toEventually(equal(0))
                    expect(defaults.array(forKey: logger.storageKey)).toEventually(beEmpty())
                    expect(originalEventRetryCount).toEventually(equal(1))
                }

                it("accumulates multiple failed events in the retry queue") {
                    logger.log(Event(user: user, name: "event_1", disableCurrentVCLogging: true))
                    logger.log(Event(user: user, name: "event_2", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    // Since we flush once, we'll have one request on the retry queue
                    expect(logger.failedRequestQueue.count).to(equal(1))
                    expect(requestCount).to(equal(1))
                }

                it("accumulates multiple failed requests in the retry queue") {
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_1", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_2", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    // Since we flush three times, we'll have three requests on the retry queue
                    expect(logger.failedRequestQueue.count).to(equal(3))
                    expect(requestCount).to(equal(3))
                }

                it("handles partial success in retry queue") {
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_ok", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_fail", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestQueue).toNot(beEmpty())

                    teardownNetwork()
                    stub(condition: isHost(LogEventHost)) { request in
                        requestCount += 1;
                        if
                            let events = request.statsig_body?["events"] as? [[String: Any]],
                            events.contains(where: { $0["eventName"] as? String == "event_fail" })
                         {
                            // Request fails if it contains the "event_fail" event
                            return HTTPStubsResponse(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                        }
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                    createLogger()

                    // Should contain the "event_fail" request data
                    expect(logger.failedRequestQueue.count).toEventually(equal(1))
                }


                it("compresses the request data") {
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestQueue).toNot(beEmpty())

                    // Verify that the request had a compressed body
                    let requestBody = lastRequest?.ohhttpStubs_httpBody
                    expect(requestBody).toNot(beNil())
                    expect(try requestBody?.gunzipped()).toNot(throwError())

                    // Verify that the failed request queue is not compressed
                    let uncompressedBody = logger.failedRequestQueue.first
                    expect(uncompressedBody).toNot(beNil())
                    expect(try uncompressedBody?.gunzipped()).to(throwError())

                    // Try again with failures
                    let currentRequestCount = requestCount
                    logger.retryFailedRequests(forUser: user)
                    expect(requestCount).toEventually(beGreaterThan(currentRequestCount))
                    expect(logger.failedRequestQueue).toEventuallyNot(beEmpty())

                    // Verify that the request body didn't change between retries
                    expect(lastRequest?.ohhttpStubs_httpBody).to(equal(requestBody))
                    // Verify that the queue data didn't change between retries
                    expect(logger.failedRequestQueue.first).to(equal(uncompressedBody))

                    // Try again with success
                    teardownNetwork()
                    stubOK()

                    // Verify that the request body didn't change between retries
                    expect(lastRequest?.ohhttpStubs_httpBody).to(equal(requestBody))
                }
            }
        }
    }
}
