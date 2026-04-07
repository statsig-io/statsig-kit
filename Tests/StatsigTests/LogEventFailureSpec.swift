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
        forUser user: StatsigUser,
        uncompressedBody: Data,
        completion: @escaping ((String?) -> Void)
    ) {
        let work = { [weak self] in
            guard let it = self else { return }
            completion(it.responseError)
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

            var logger: EventLogger!

            describe("threads") {
                var network: MockNetwork!

                beforeEach {
                    EventLogger.deleteLocalStorage(sdkKey: sdkKey)

                    network = MockNetwork()
                    network.responseError = "Nah uh uh uh"
                    network.responseData = "{}".data(using: .utf8)

                    logger = EventLogger(sdkKey: sdkKey, user: user, networkService: network)
                    logger.log(Event(user: user, name: "an_event", disableCurrentVCLogging: true))
                }

                afterEach {
                    EventLogger.deleteLocalStorage(sdkKey: sdkKey)
                }

                it("handles errors that come back on the calling thread") {
                    network.responseIsAsync = false
                    waitUntil { done in logger.flush(completion: done) }
                    expect(network.timesCalled).to(equal(1))
                    expect(logger.failedRequestStore.requests.count).to(equal(1))
                }

                it("handles errors that come back on a bg thread") {
                    network.responseIsAsync = true
                    waitUntil { done in logger.flush(completion: done) }
                    expect(network.timesCalled).to(equal(1))
                    expect(logger.failedRequestStore.requests.count).to(equal(1))
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
                    logger = EventLogger(sdkKey: sdkKey, user: user, networkService: ns)
                    logger.retryFailedRequests(forUser: user)
                }

                beforeEach {
                    EventLogger.deleteLocalStorage(sdkKey: sdkKey)
                    lastRequest = nil
                    NetworkService.disableCompression = false
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
                    EventLogger.deleteLocalStorage(sdkKey: sdkKey)
                }

                func stubError() {
                    stub(condition: isHost(LogEventHost)) { request in
                        requestCount += 1
                        lastRequest = request
                        // Use a cancelled error to prevent the network retry logic
                        return HTTPStubsResponse(
                            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                    }
                }

                func stubOK() {
                    stub(condition: isHost(LogEventHost)) { request in
                        requestCount += 1
                        lastRequest = request
                        if let events = request.statsig_body?["events"] as? [[String: Any]] {
                            originalEventRetryCount +=
                                events.filter({ $0["eventName"] as? String == "an_event" }).count
                        }
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                }

                it("an event failed multiple times isn't duplicated in the queue") {
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestStore.requests).toNot(beEmpty())

                    // Shutdown the current logger. Create a new one.
                    waitUntil { done in logger.stop(completion: done) }
                    createLogger()

                    expect(logger.failedRequestStore.requests).toEventuallyNot(beEmpty())

                    // Check if the initial event isn't duplicated in the queue
                    var initialEventQueued = 0
                    for request in logger.failedRequestStore.requests {
                        // Decode events from saved body
                        guard
                            let body = try? JSONSerialization.jsonObject(
                                with: request.body,
                                options: []) as? [String: Any],
                            let events = body["events"] as? [[String: Any]]
                        else {
                            continue
                        }
                        // Check if body is the initial event
                        for event in events {
                            if event["eventName"] as? String == "an_event" {
                                initialEventQueued += 1
                            }
                        }
                    }
                    expect(initialEventQueued).to(equal(1))
                }

                it("persists failed events across SDK initializations") {
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestStore.requests.count).to(equal(1))  // Initial event + new event

                    // Shutdown the current logger
                    waitUntil { done in logger.stop(completion: done) }

                    // Verify events were persisted in the failed request store
                    expect(
                        decodeFailedLogRequestStore(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: sdkKey
                        )
                    )
                    .toNot(beNil())
                    expect(
                        readPersistedFailedRequests(
                            storageAdapter: logger.failedRequestStore.storageAdapter,
                            sdkKey: sdkKey
                        )
                    )
                    .toNot(beEmpty())

                    teardownNetwork()
                    stubError()
                    createLogger()

                    expect(requestCount).toEventually(beGreaterThanOrEqualTo(1))
                    expect(logger.failedRequestStore.requests).toEventuallyNot(beEmpty())
                }

                it("retries failed requests on next initialization") {
                    waitUntil { done in logger.stop(completion: done) }
                    expect(requestCount).to(equal(1))
                    expect(logger.failedRequestStore.requests.count).to(equal(1))
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
                        )
                    )
                    .toEventuallyNot(beEmpty())

                    teardownNetwork()
                    stubOK()
                    createLogger()

                    expect(requestCount).toEventually(equal(1))
                    expect(logger.failedRequestStore.requests.count).toEventually(equal(0))
                    expect(originalEventRetryCount).toEventually(equal(1))
                }

                it("accumulates multiple failed events in the retry queue") {
                    logger.log(Event(user: user, name: "event_1", disableCurrentVCLogging: true))
                    logger.log(Event(user: user, name: "event_2", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    // Since we flush once, we'll have one request on the retry queue
                    expect(logger.failedRequestStore.requests.count).to(equal(1))
                    expect(requestCount).to(equal(1))
                }

                it("accumulates multiple failed requests in the retry queue") {
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_1", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_2", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    // Since we flush three times, we'll have three requests on the retry queue
                    expect(logger.failedRequestStore.requests.count).to(equal(3))
                    expect(requestCount).to(equal(3))
                }

                it("handles partial success in retry queue") {
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_ok", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    logger.log(Event(user: user, name: "event_fail", disableCurrentVCLogging: true))
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestStore.requests).toNot(beEmpty())

                    teardownNetwork()
                    stub(condition: isHost(LogEventHost)) { request in
                        requestCount += 1
                        if let events = request.statsig_body?["events"] as? [[String: Any]],
                            events.contains(where: { $0["eventName"] as? String == "event_fail" })
                        {
                            // Request fails if it contains the "event_fail" event
                            return HTTPStubsResponse(
                                error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
                        }
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }
                    createLogger()

                    // Should contain the "event_fail" request data
                    expect(logger.failedRequestStore.requests.count).toEventually(equal(1))
                }

                it("updates lastFailedAtMs when retries fail again") {
                    let initialLastFailedAtMs: UInt64 = 1
                    teardownNetwork()
                    stubError()

                    logger = EventLogger(sdkKey: sdkKey, user: user, networkService: ns)
                    logger.failedRequestStore.addRequests([
                        FailedLogRequest(
                            body: Data(count: 16),
                            lastFailedAtMs: initialLastFailedAtMs,
                            requestEventCount: 3
                        )
                    ])
                    logger.failedRequestStore.persist()

                    createLogger()

                    expect(logger.failedRequestStore.requests.count).toEventually(equal(1))
                    expect(logger.failedRequestStore.requests.first?.lastFailedAtMs)
                        .toEventually(beGreaterThan(initialLastFailedAtMs))
                }

                it("compresses the request data") {
                    waitUntil { done in logger.flush(completion: done) }
                    expect(logger.failedRequestStore.requests).toNot(beEmpty())

                    // Verify that the request had a compressed body
                    let requestBody = lastRequest?.ohhttpStubs_httpBody
                    expect(requestBody).toNot(beNil())
                    expect(try requestBody?.gunzipped()).toNot(throwError())

                    // Verify that the failed request queue is not compressed
                    let uncompressedBody = logger.failedRequestStore.requests.first?.body
                    expect(uncompressedBody).toNot(beNil())
                    expect(try uncompressedBody?.gunzipped()).to(throwError())

                    // Try again with failures
                    let currentRequestCount = requestCount
                    logger.retryFailedRequests(forUser: user)
                    expect(requestCount).toEventually(beGreaterThan(currentRequestCount))
                    expect(logger.failedRequestStore.requests).toEventuallyNot(beEmpty())

                    // Verify that the request body didn't change between retries
                    expect(lastRequest?.ohhttpStubs_httpBody).to(equal(requestBody))
                    // Verify that the queue data didn't change between retries
                    expect(logger.failedRequestStore.requests.first?.body).to(
                        equal(uncompressedBody))

                    // Try again with success
                    teardownNetwork()
                    stubOK()

                    // Verify that the request body didn't change between retries
                    expect(lastRequest?.ohhttpStubs_httpBody).to(equal(requestBody))
                }
            }

            describe("local storage persistence on network failure") {
                let providerSDKKey = "client-key-provider"
                var provider: MockStorageProvider!
                var providerLogger: EventLogger!
                var providerRequestCount = 0
                let providerUser = StatsigUser(userID: "provider-user")

                func makeProviderNetworkService() -> NetworkService {
                    let options = StatsigOptions(storageProvider: provider)
                    let store = InternalStore(providerSDKKey, providerUser, options: options)
                    return NetworkService(sdkKey: providerSDKKey, options: options, store: store)
                }

                func createProviderLogger() {
                    providerLogger = EventLogger(
                        sdkKey: providerSDKKey,
                        user: providerUser,
                        networkService: makeProviderNetworkService()
                    )
                }

                beforeEach {
                    provider = MockStorageProvider()
                    FailedLogRequestStore.deleteLocalStorage(
                        sdkKey: providerSDKKey,
                        storageAdapter: StorageProviderToAdapter(
                            storageProvider: provider
                        )
                    )
                    providerRequestCount = 0

                    stub(condition: isHost(LogEventHost)) { request in
                        providerRequestCount += 1
                        return HTTPStubsResponse(
                            error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
                        )
                    }

                    createProviderLogger()
                    providerLogger.log(
                        Event(
                            user: providerUser,
                            name: "stored_on_failure",
                            disableCurrentVCLogging: true
                        ))
                }

                afterEach {
                    HTTPStubs.removeAllStubs()
                    provider.storage = [:]
                    FailedLogRequestStore.clearCachedInstances()
                    StorageService.clearCachedInstances()
                }

                it("stores failed requests via the storage adapter when the network request fails")
                {
                    waitUntil { done in
                        providerLogger.flush(completion: done)
                    }

                    expect(providerRequestCount).to(equal(1))
                    expect(
                        decodeFailedLogRequestStore(
                            storageAdapter: providerLogger.failedRequestStore.storageAdapter,
                            sdkKey: providerSDKKey
                        )?.requests.count
                    ).toEventually(equal(1))
                }

                it("reloads failed requests from local storage on the next logger instance") {
                    waitUntil { done in
                        providerLogger.flush(completion: done)
                    }

                    let persistedBodies =
                        decodeFailedLogRequestStore(
                            storageAdapter: providerLogger.failedRequestStore.storageAdapter,
                            sdkKey: providerSDKKey
                        )?.requests.map(\.body)

                    FailedLogRequestStore.clearCachedInstances()
                    StorageService.clearCachedInstances()

                    createProviderLogger()

                    expect(providerLogger.failedRequestStore.requests.map(\.body)).toEventually(
                        equal(persistedBodies)
                    )
                }
            }
        }
    }
}
