import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class ApiOverrideSpec: BaseSpec {
    override func spec() {
        super.spec()

        var request: URLRequest?

        describe("When Main API Overridden") {
            func start() {
                let opts = StatsigOptions(
                    api: "http://api.override.com", eventLoggingApi: "http://api.override.com")
                request = TestUtils.startWithStatusAndWait(options: opts)
            }

            func startWithURLs() {
                let opts = StatsigOptions(
                    initializationURL: URL(string: "http://api.override.com/setup"),
                    eventLoggingURL: URL(string: "http://api.override.com/st"))
                request = TestUtils.startWithStatusAndWait(options: opts)
            }

            afterSuite {
                TestUtils.resetDefaultURLs()
            }

            it("calls initialize on the overridden api") {
                start()
                expect(request?.url?.absoluteString)
                    .to(equal("http://api.override.com/v1/initialize"))
            }

            it("calls log_event on the overridden api") {
                start()
                var hitLog = false
                TestUtils.captureLogs(host: "api.override.com") { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }

            it("calls initialize on the overridden api using URLs") {
                startWithURLs()
                expect(request?.url?.absoluteString).to(equal("http://api.override.com/setup"))
            }

            it("calls log_event on the overridden api using URLs") {
                startWithURLs()
                var hitLog = false
                TestUtils.captureLogs(host: "api.override.com", path: "/st") { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }
        }

        describe("When Not Overridden") {
            func start() {
                request = TestUtils.startWithStatusAndWait()
            }

            it("calls initialize on the statsig api") {
                start()
                expect(request?.url?.absoluteString)
                    .to(equal("https://featureassets.org/v1/initialize"))
            }

            it("calls log_event on the statsig api") {
                start()
                var hitLog = false
                TestUtils.captureLogs(host: LogEventHost) { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }
        }

        describe("When Logging API Overridden") {
            func start() {
                let opts = StatsigOptions(eventLoggingApi: "http://api.log.co.nz/")
                request = TestUtils.startWithStatusAndWait(options: opts)
            }

            func startWithURLs() {
                let opts = StatsigOptions(eventLoggingURL: URL(string: "http://api.log.co.nz/st"))
                request = TestUtils.startWithStatusAndWait(options: opts)
            }

            it("calls initialize on the statsig api") {
                start()
                expect(request?.url?.absoluteString)
                    .to(equal("https://featureassets.org/v1/initialize"))
            }

            it("calls log_event on the overridden api.log.co.nz api") {
                start()
                var hitLog = false
                TestUtils.captureLogs(host: "api.log.co.nz") { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }

            it("calls initialize on the statsig api using URLs") {
                startWithURLs()
                expect(request?.url?.absoluteString)
                    .to(equal("https://featureassets.org/v1/initialize"))
            }

            it("calls log_event on the overridden api.log.co.nz api using URLs") {
                startWithURLs()
                var hitLog = false
                TestUtils.captureLogs(host: "api.log.co.nz", path: "/st") { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }
        }

        describe("When Main and Logging API Overridden") {
            func start() {
                let opts = StatsigOptions(
                    api: "http://main.api", eventLoggingApi: "http://api.log.co.nz")
                request = TestUtils.startWithStatusAndWait(options: opts)
            }

            func startWithURLs() {
                let opts = StatsigOptions(
                    initializationURL: URL(string: "http://main.api/setup"),
                    eventLoggingURL: URL(string: "http://api.log.co.nz/st"))
                request = TestUtils.startWithStatusAndWait(options: opts)
            }

            it("calls initialize on the overridden api") {
                start()
                expect(request?.url?.absoluteString).to(equal("http://main.api/v1/initialize"))
            }

            it("calls log_event on the overridden api.log.co.nz api") {
                start()
                var hitLog = false
                TestUtils.captureLogs(host: "api.log.co.nz") { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }

            it("calls initialize on the overridden api using URLs") {
                startWithURLs()
                expect(request?.url?.absoluteString).to(equal("http://main.api/setup"))
            }

            it("calls log_event on the overridden api.log.co.nz api using URLs") {
                startWithURLs()
                var hitLog = false
                TestUtils.captureLogs(host: "api.log.co.nz", path: "/st") { logs in
                    hitLog = true
                }

                Statsig.logEvent("test_event")
                Statsig.shutdown()
                expect(hitLog).toEventually(beTrue())
            }
        }

    }
}
