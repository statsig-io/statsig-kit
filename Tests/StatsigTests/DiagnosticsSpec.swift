import Foundation
import Nimble
import Quick
import XCTest

@testable import Statsig

final class DiagnosticsSpec: BaseSpec {

    final class NoopDiagnosticsEventLogger: EventLogger {
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
        }
    }
}
