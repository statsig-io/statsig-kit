import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class AppLifecycleSpec: BaseSpec {
    override func spec() {
        super.spec()

        var logger: SpiedEventLogger!

        func startAndLog(shutdownOnBackground: Bool, tag: String) {
            let opts = StatsigOptions(shutdownOnBackground: shutdownOnBackground)
            NetworkService.defaultInitializationURL = URL(
                string: "http://AppLifecycleSpec::\(tag)/v1/initialize")

            _ = TestUtils.startWithStatusAndWait(options: opts)

            logger = SpiedEventLogger(
                sdkKey: "client-key",
                user: StatsigUser(),
                networkService: Statsig.client!.logger.networkService,
                userDefaults: MockDefaults()
            )
            Statsig.client?.logger = logger
            Statsig.logEvent("my_event")
        }

        afterEach {
            Statsig.shutdown()
            TestUtils.resetDefaultURLs()
        }

        it("shuts down the logger on app background when shutdownOnBackground is true") {
            startAndLog(shutdownOnBackground: true, tag: "Shutdown")

            NotificationCenter.default.post(
                name: PlatformCompatibility.willResignActiveNotification,
                object: nil
            )

            expect(logger.timesShutdownCalled).toEventually(equal(1))
            expect(logger.timesFlushCalled).to(equal(0))
        }

        it("flushes the logger on app background when shutdownOnBackground is false") {
            startAndLog(shutdownOnBackground: false, tag: "Flush")

            NotificationCenter.default.post(
                name: PlatformCompatibility.willResignActiveNotification,
                object: nil
            )

            expect(logger.timesFlushCalled).toEventually(equal(1))
            expect(logger.timesShutdownCalled).to(equal(0))
        }
    }
}
