import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

// Example DNS response
// Domains: ["i=assetsconfigcdn.org", "i=featureassets.org", "d=api.statsigcdn.com", "e=beyondwickedmapping.org", "e=prodregistryv2.org"]
let dnsResponse: [UInt8] = [
    0, 0, 129, 128, 0, 1, 0, 1, 0, 0, 0, 0, 13, 102, 101, 97, 116, 117, 114, 101, 97, 115, 115, 101,
    116, 115, 3, 111, 114, 103, 0, 0, 16, 0, 1, 192, 12, 0, 16, 0, 1, 0, 0, 1, 44, 0, 110, 109, 105,
    61, 97, 115, 115, 101, 116, 115, 99, 111, 110, 102, 105, 103, 99, 100, 110, 46, 111, 114, 103,
    44, 105, 61, 102, 101, 97, 116, 117, 114, 101, 97, 115, 115, 101, 116, 115, 46, 111, 114, 103,
    44, 100, 61, 97, 112, 105, 46, 115, 116, 97, 116, 115, 105, 103, 99, 100, 110, 46, 99, 111, 109,
    44, 101, 61, 98, 101, 121, 111, 110, 100, 119, 105, 99, 107, 101, 100, 109, 97, 112, 112, 105,
    110, 103, 46, 111, 114, 103, 44, 101, 61, 112, 114, 111, 100, 114, 101, 103, 105, 115, 116, 114,
    121, 118, 50, 46, 111, 114, 103,
]

class NetworkFallbackResolverSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("using NetworkFallbackResolver to fallback requests we suspect are being blocked")
        {
            let sdkKey = "client-api-key"
            let opts = StatsigOptions()

            var dnsRequestCount = 0

            beforeSuite {
                NetworkFallbackResolver.fallbackEnabled = true
            }

            afterSuite {
                NetworkFallbackResolver.fallbackEnabled = false
            }

            beforeEach {
                TestUtils.clearStorage()
                TestUtils.resetDefaultURLs()

                // Stub DNS request
                dnsRequestCount = 0
                stub(condition: isHost("cloudflare-dns.com")) { request in
                    dnsRequestCount += 1
                    return HTTPStubsResponse(data: Data(dnsResponse), statusCode: 200, headers: nil)
                }
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                TestUtils.clearStorage()
                NetworkFallbackResolver.now = { Date() }
            }

            it("handles concurrent domain failures and fallback reads and writes") {
                let user = StatsigUser(userID: "concurrent-fallback")
                let store = InternalStore(sdkKey, user, options: opts)
                let resolver = NetworkFallbackResolver(
                    sdkKey: sdkKey, store: store,
                    errorBoundary: ErrorBoundary.boundary(clientKey: sdkKey, statsigOptions: opts))
                let now = Date()
                NetworkFallbackResolver.now = { now }
                let completions = LockedValue(wrappedValue: [Endpoint: Int]())
                let requests = LockedValue(wrappedValue: 0)
                let failedUpdates = LockedValue(wrappedValue: 0)
                let endpoints: [Endpoint] = [.initialize, .logEvent]

                // Override the suite stub with a synchronized counter for concurrent DNS requests.
                stub(condition: isHost("cloudflare-dns.com")) { _ in
                    requests.withLock { $0 += 1 }
                    return HTTPStubsResponse(data: Data(dnsResponse), statusCode: 200, headers: nil)
                }

                let group = DispatchGroup()
                let start = DispatchSemaphore(value: 0)
                for worker in 0..<8 {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        start.wait()
                        let endpoint = endpoints[worker % endpoints.count]
                        for _ in 0..<250 {
                            // Mirror overlapping domain-failure completions from NetworkService.
                            _ = resolver.getActiveFallbackURL(endpoint: endpoint)
                            resolver.tryFetchUpdatedFallbackInfo(endpoint: endpoint) { updated in
                                if !updated {
                                    failedUpdates.withLock { $0 += 1 }
                                }
                                // Reenter the resolver to ensure callbacks run outside its lock.
                                resolver.tryBumpExpiryTime(endpoint: endpoint)
                                _ = resolver.getActiveFallbackURL(endpoint: endpoint)
                                completions.withLock { $0[endpoint, default: 0] += 1 }
                            }
                            resolver.tryBumpExpiryTime(endpoint: endpoint)
                            _ = resolver.getActiveFallbackURL(endpoint: endpoint)
                        }
                        group.leave()
                    }
                }
                for _ in 0..<8 {
                    start.signal()
                }
                waitUntil(timeout: .seconds(15)) { done in
                    group.notify(queue: .main) { done() }
                }
                expect(completions.get().values.reduce(0, +)).toEventually(
                    equal(2), timeout: .seconds(15))
                expect(requests.get()).to(equal(2))
                expect(failedUpdates.get()).to(equal(0))
                expect(completions.get()[.initialize]).to(equal(1))
                expect(completions.get()[.logEvent]).to(equal(1))
                expect(resolver.getActiveFallbackURL(endpoint: .initialize)?.host).to(
                    equal("assetsconfigcdn.org"))
                expect(resolver.getActiveFallbackURL(endpoint: .logEvent)?.host).to(
                    equal("beyondwickedmapping.org"))
                // Drain asynchronous persistence before suite cleanup.
                store.storeQueue.sync(flags: .barrier) {}
            }

            it("should fallback on initialize") {
                var triedRequestingApiHost = false
                var fallbackURLReceivedRequest = false

                // Stub ApiHost
                stub(condition: isHost(ApiHost)) { request in
                    triedRequestingApiHost = true
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                }
                // Stub fallback URL
                stub(condition: isHost("assetsconfigcdn.org")) { request in
                    fallbackURLReceivedRequest = true
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                var fetchError: StatsigClientError? = nil

                let user = StatsigUser(userID: "jkw")
                let store = InternalStore(sdkKey, user, options: opts)
                let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)

                // Make request
                waitUntil { done in
                    ns.fetchInitialValues(
                        for: user, sinceTime: 0, previousDerivedFields: [:], fullChecksum: nil
                    ) { err in
                        fetchError = err
                        done()
                    }
                }

                expect(triedRequestingApiHost).to(equal(true))
                expect(dnsRequestCount).to(equal(1))
                expect(fallbackURLReceivedRequest).to(equal(true))
                expect(fetchError).to(beNil())
            }

            it("should fallback on register") {
                var triedRequestingLogEventHost = false
                var fallbackURLReceivedRequest = false

                // Stub LogEventHost
                stub(condition: isHost(LogEventHost)) { request in
                    triedRequestingLogEventHost = true
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                }
                // Stub fallback URL
                stub(condition: isHost("beyondwickedmapping.org")) { request in
                    fallbackURLReceivedRequest = true
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let user = StatsigUser(userID: "jkw")
                let store = InternalStore(sdkKey, user, options: opts)
                let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)

                // Make request
                let event1 = Event(
                    user: user, name: "test_event1", value: 1, disableCurrentVCLogging: false)
                let body = try ns.prepareEventRequestBody(forUser: user, events: [event1]).get()
                waitUntil { done in
                    ns.sendEvents(forUser: user, uncompressedBody: body) { err in
                        done()
                    }
                }

                expect(triedRequestingLogEventHost).to(equal(true))
                expect(dnsRequestCount).to(equal(1))
                expect(fallbackURLReceivedRequest).to(equal(true))
            }

            it("should use fallback URL if the normal URL failed earlier") {
                var originalURLRequestCount = 0
                var fallbackURLRequestCount = 0

                // Stub ApiHost
                stub(condition: isHost(ApiHost)) { request in
                    originalURLRequestCount += 1
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                }
                // Stub fallback URL
                stub(condition: isHost("assetsconfigcdn.org")) { request in
                    fallbackURLRequestCount += 1
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let user = StatsigUser(userID: "jkw")
                let store = InternalStore(sdkKey, user, options: opts)
                let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)

                // Make request
                waitUntil { done in
                    ns.fetchInitialValues(
                        for: user, sinceTime: 0, previousDerivedFields: [:], fullChecksum: nil
                    ) { err in
                        done()
                    }
                }

                let store2 = InternalStore(sdkKey, user, options: opts)
                let ns2 = NetworkService(sdkKey: sdkKey, options: opts, store: store2)

                waitUntil { done in
                    ns2.fetchInitialValues(
                        for: user, sinceTime: 0, previousDerivedFields: [:], fullChecksum: nil
                    ) { err in
                        done()
                    }
                }

                expect(originalURLRequestCount).to(equal(1))
                expect(dnsRequestCount).to(equal(1))
                expect(fallbackURLRequestCount).to(equal(2))
            }

            it("shouldn't use fallback URLs if the URL overrides are set") {
                var triedRequestingApiHost = false
                var triedRequestingOverrideHost = false
                var fallbackURLReceivedRequest = false
                let overrideHost = "fallbacktest"

                // Stub overrideHost
                stub(condition: isHost(overrideHost)) { request in
                    triedRequestingOverrideHost = true
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                }
                // Stub ApiHost
                stub(condition: isHost(ApiHost)) { request in
                    triedRequestingApiHost = true
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                }
                // Stub fallback URL
                stub(condition: isHost("assetsconfigcdn.org")) { request in
                    fallbackURLReceivedRequest = true
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let user = StatsigUser(userID: "jkw")
                let opts = StatsigOptions(
                    initializationURL: URL(string: "https://\(overrideHost)/v1/setup"))
                let store = InternalStore(sdkKey, user, options: opts)
                let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)

                // Make request
                waitUntil { done in
                    ns.fetchInitialValues(
                        for: user, sinceTime: 0, previousDerivedFields: [:], fullChecksum: nil
                    ) { err in
                        done()
                    }
                }

                expect(triedRequestingOverrideHost).to(equal(true))
                expect(triedRequestingApiHost).to(equal(false))
                expect(dnsRequestCount).to(equal(0))
                expect(fallbackURLReceivedRequest).to(equal(false))
            }

            it("shouldn't use fallback URLs if they expired") {
                var originalURLRequestCount = 0
                var fallbackURLRequestCount = 0

                // Mock NetworkFallbackResolver's current date
                var date = Date()
                NetworkFallbackResolver.now = { date }

                // Stub ApiHost
                stub(condition: isHost(ApiHost)) { request in
                    originalURLRequestCount += 1
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
                }
                // Stub fallback URL
                stub(condition: isHost("assetsconfigcdn.org")) { request in
                    fallbackURLRequestCount += 1
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let user = StatsigUser(userID: "jkw")
                let store = InternalStore(sdkKey, user, options: opts)
                let ns = NetworkService(sdkKey: sdkKey, options: opts, store: store)

                // Make request
                waitUntil { done in
                    ns.fetchInitialValues(
                        for: user, sinceTime: 0, previousDerivedFields: [:], fullChecksum: nil
                    ) { err in
                        done()
                    }
                }

                // Advance mocked time past the expiration time
                date = date.addingTimeInterval(2 * DEFAULT_TTL_SECONDS)

                // Change the api stub to avoid another fallback
                stub(condition: isHost(ApiHost)) { request in
                    originalURLRequestCount += 1
                    // Fail request in a way that triggers a fallback
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                // Make request
                waitUntil { done in
                    ns.fetchInitialValues(
                        for: user, sinceTime: 0, previousDerivedFields: [:], fullChecksum: nil
                    ) { err in
                        done()
                    }
                }

                expect(originalURLRequestCount).to(equal(2))
                expect(dnsRequestCount).to(equal(1))
                expect(fallbackURLRequestCount).to(equal(1))
            }
        }
    }
}
