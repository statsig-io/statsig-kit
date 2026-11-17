import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class DiagnosticsSpec: BaseSpec {

    class NoopDiagnosticsEventLogger: EventLogger {
        init() {
            let user = StatsigUser(userID: "diag-concurrency-user")
            let options = StatsigOptions(eventLoggingEnabled: false, disableDiagnostics: true)
            let store = InternalStore("client-key", user, options: options)
            let networkService = NetworkService(
                sdkKey: "client-key", options: options, store: store)

            super.init(
                sdkKey: "client-key", user: user,
                networkService: networkService, userDefaults: MockDefaults()
            )
        }

        override func log(_ event: Event, exposureDedupeKey: DedupeKey? = nil) {}
    }

    final class RecordingDiagnosticsEventLogger: NoopDiagnosticsEventLogger {
        var recordedEvents: [Event] = []

        override func log(_ event: Event, exposureDedupeKey: DedupeKey? = nil) {
            recordedEvents.append(event)
        }
    }

    override func spec() {
        super.spec()

        describe("Diagnostics") {
            it("starts many Diagnostics instances in parallel (deadlock repro)") {
                let logger = NoopDiagnosticsEventLogger()
                let queue = DispatchQueue(
                    label: "com.statsig.tests.DiagnosticsConcurrency", attributes: .concurrent)
                let totalWorkers = 1000
                let group = DispatchGroup()

                for i in 0..<totalWorkers {
                    group.enter()
                    queue.async(group: group) {
                        Diagnostics.boot(nil)

                        Diagnostics.mark?.overall.start()
                        Diagnostics.mark?.overall.end(
                            success: true, details: .uninitialized(), errorMessage: nil)

                        Diagnostics.log(
                            logger, user: StatsigUser(userID: "diag-\(i)"), context: .initialize)

                        Diagnostics.shutdown()
                        group.leave()
                    }
                }

                // Bounded wait to avoid a full suite hang when deadlock reproduces.
                let result = group.wait(timeout: .now() + .seconds(2))
                expect(result).to(
                    equal(DispatchTimeoutResult.success),
                    description: result == .timedOut
                        ? "Timed out waiting for concurrent Diagnostics operations, deadlock/crash likely triggered"
                        : nil)
            }

            it("logs an update-user operation exactly once") {
                let logger = RecordingDiagnosticsEventLogger()
                let diagnostics = UpdateUserDiagnostics()
                let user = StatsigUser(userID: "update-user")

                diagnostics.start()
                diagnostics.complete(
                    logger,
                    user: user,
                    success: true,
                    details: .uninitialized(),
                    errorMessage: nil)
                diagnostics.complete(
                    logger,
                    user: user,
                    success: true,
                    details: .uninitialized(),
                    errorMessage: nil)

                expect(logger.recordedEvents).to(haveCount(1))
                let event = logger.recordedEvents.first as? DiagnosticsEvent
                expect(event?.context).to(equal(MarkerContext.updateUser.rawValue))
                expect(event?.markers).to(haveCount(2))
                expect(event?.markers.first?["action"] as? String).to(equal("start"))
                expect(event?.markers.last?["action"] as? String).to(equal("end"))
            }

            it("uses the current client's diagnostics option for update-user recording") {
                Diagnostics.boot(StatsigOptions(disableDiagnostics: true))
                expect(Diagnostics.startUpdateUser(disabled: true)).to(beNil())
                expect(Diagnostics.startUpdateUser(disabled: false)).toNot(beNil())
                Diagnostics.shutdown()
            }

            for failure in ["http", "disconnect", "timeout"] {
                for hasCache in [false, true] {
                    it("finalizes update-user diagnostics for \(failure) with cache=\(hasCache)") {
                        let originalUser = StatsigUser(userID: "diagnostics-original")
                        let updatedUser =
                            hasCache ? originalUser : StatsigUser(userID: "diagnostics-uncached")
                        var bootstrapValues = StatsigSpec.mockUserValues
                        bootstrapValues[InternalStore.lcutKey] = UInt64(111)
                        bootstrapValues[InternalStore.evalTimeKey] = UInt64(222)
                        let options = StatsigOptions(
                            initTimeout: failure == "timeout" ? 0.05 : 0,
                            EXPERIMENTAL_storageType: .legacy,
                            initializeValues: bootstrapValues,
                            eventLoggingEnabled: false)
                        let client = StatsigClient(
                            sdkKey: "client-key",
                            user: originalUser,
                            options: options,
                            userDefaults: MockDefaults(),
                            cacheType: .user_defaults,
                            completionWithResult: nil)
                        let logger = RecordingDiagnosticsEventLogger()
                        client.logger.stop()
                        client.logger = logger
                        defer {
                            client.shutdown()
                            HTTPStubs.removeAllStubs()
                        }

                        stub(condition: isHost(ApiHost)) { _ in
                            if failure == "disconnect" {
                                return HTTPStubsResponse(
                                    error: NSError(
                                        domain: NSURLErrorDomain,
                                        code: NSURLErrorNotConnectedToInternet))
                            }
                            if failure == "timeout" {
                                return HTTPStubsResponse(
                                    jsonObject: StatsigSpec.mockUserValues,
                                    statusCode: 200,
                                    headers: nil
                                ).responseTime(1)
                            }
                            return HTTPStubsResponse(
                                data: Data(), statusCode: 403, headers: nil)
                        }

                        var callbackCount = 0
                        var updateError: StatsigClientError?
                        waitUntil(timeout: .seconds(2)) { done in
                            client.updateUserWithResult(updatedUser) { error in
                                callbackCount += 1
                                updateError = error
                                done()
                            }
                        }

                        expect(callbackCount).to(equal(1))
                        expect(updateError).toNot(beNil())
                        let events = logger.recordedEvents.compactMap { $0 as? DiagnosticsEvent }
                        expect(events).to(haveCount(1))
                        let event = events.first
                        expect(event?.context).to(equal(MarkerContext.updateUser.rawValue))
                        expect(event?.userData["userID"] as? String).to(equal(updatedUser.userID))
                        let endMarker = event?.markers.last
                        expect(endMarker?["key"] as? String).to(equal("overall"))
                        expect(endMarker?["action"] as? String).to(equal("end"))
                        expect(endMarker?["success"] as? Bool).to(beFalse())
                        let details = endMarker?["evaluationDetails"] as? [String: Any]
                        expect(details?["reason"] as? String).to(
                            equal(
                                hasCache
                                    ? EvaluationSource.Cache.rawValue
                                    : EvaluationSource.NoValues.rawValue))
                        if hasCache {
                            expect(details?["lcut"] as? UInt64).to(equal(111))
                            expect(details?["receivedAt"] as? UInt64).to(equal(222))
                        }
                    }
                }
            }

            it("preserves selected-storage metadata in bootstrap update diagnostics") {
                let storageProvider = MockStorageProvider()
                let userDefaults = StorageProviderBasedUserDefaults(
                    storageProvider: storageProvider)
                let stableID = "selected-storage-stable-id"
                let options = StatsigOptions(
                    overrideStableID: stableID,
                    initializeValues: StatsigSpec.mockUserValues,
                    storageProvider: storageProvider)
                let client = StatsigClient(
                    sdkKey: "client-key",
                    user: StatsigUser(userID: "diagnostics-user-a"),
                    options: options,
                    userDefaults: userDefaults,
                    cacheType: .provider,
                    rebindStableID: true,
                    completionWithResult: nil)
                defer { client.shutdown() }
                let logger = RecordingDiagnosticsEventLogger()
                client.logger = logger
                var bootstrapValues = StatsigSpec.mockUserValues
                bootstrapValues[InternalStore.lcutKey] = UInt64(222)

                client.updateUserWithResult(
                    StatsigUser(userID: "diagnostics-user-b"),
                    values: bootstrapValues)

                expect(logger.recordedEvents).toEventually(haveCount(1))
                let event = logger.recordedEvents.first as? DiagnosticsEvent
                let endMarker = event?.markers.last
                expect(client.userDefaults is StorageProviderBasedUserDefaults).to(beTrue())
                expect(event?.userData["userID"] as? String).to(equal("diagnostics-user-b"))
                expect(client.getStableID()).to(equal(stableID))
                let details = endMarker?["evaluationDetails"] as? [String: Any]
                expect(details?["reason"] as? String).to(
                    equal(EvaluationSource.Bootstrap.rawValue))
                expect(details?["lcut"] as? UInt64).to(equal(222))
            }
        }
    }
}
