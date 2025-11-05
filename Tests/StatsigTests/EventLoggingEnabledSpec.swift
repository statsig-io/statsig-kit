import Foundation

import Nimble
import Quick
import OHHTTPStubs
#if !COCOAPODS
import OHHTTPStubsSwift
#endif
@testable import Statsig

class EventLoggingEnabledSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("eventLoggingEnabled option") {
            beforeEach {
                TestUtils.clearStorage()
            }

            afterEach {
                Statsig.shutdown()
                HTTPStubs.removeAllStubs()
                TestUtils.clearStorage()
            }

            it("sends events when initialized without overriding logging") {
                var capturedEvents = [[String: Any]]()
                TestUtils.captureLogs { body in
                    if let events = body["events"] as? [[String: Any]] {
                        capturedEvents.append(contentsOf: events)
                    }
                }

                let options = StatsigOptions(eventLoggingEnabled: true, disableDiagnostics: true)
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues,
                    "client-api-key",
                    StatsigUser(userID: "test-user"),
                    200,
                    options: options
                )

                Statsig.logEvent("default_event")
                Statsig.flush()

                expect(capturedEvents.contains(where: { $0["eventName"] as? String == "default_event" })).toEventually(beTrue(), timeout: .seconds(5))
            }

            it("sends events when initialized with logging enabled") {
                var capturedEvents = [[String: Any]]()
                TestUtils.captureLogs { body in
                    if let events = body["events"] as? [[String: Any]] {
                        capturedEvents.append(contentsOf: events)
                    }
                }

                let options = StatsigOptions(eventLoggingEnabled: true, disableDiagnostics: true)
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues,
                    "client-api-key",
                    StatsigUser(userID: "test-user"),
                    200,
                    options: options
                )

                Statsig.logEvent("test_event")
                Statsig.flush()

                expect(capturedEvents.contains(where: { $0["eventName"] as? String == "test_event" })).toEventually(beTrue(), timeout: .seconds(5))
            }

            it("does not send events when logging is disabled") {
                let lock = NSLock()
                var capturedEventNames = [String]()
                TestUtils.captureLogs { body in
                    if let events = body["events"] as? [[String: Any]] {
                        let names = events.compactMap { $0["eventName"] as? String }
                        lock.lock()
                        capturedEventNames.append(contentsOf: names)
                        lock.unlock()
                    }
                }

                let options = StatsigOptions(eventLoggingEnabled: false, disableDiagnostics: true)
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues,
                    "client-api-key",
                    StatsigUser(userID: "test-user"),
                    200,
                    options: options
                )

                Statsig.logEvent("event_while_disabled")
                Statsig.flush()

                guard let logger = Statsig.client?.logger else {
                    fail("Failed to obtain logger"); return
                }

                logger.logQueue.sync {}
                skipFrame()

                lock.lock()
                let eventsAfterFlush = capturedEventNames
                lock.unlock()

                expect(eventsAfterFlush).to(beEmpty())
            }

            it("sends saved events when logging is re-enabled") {
                let lock = NSLock()
                var capturedEventNames = [String]()
                TestUtils.captureLogs { body in
                    if let events = body["events"] as? [[String: Any]] {
                        let names = events.compactMap { $0["eventName"] as? String }
                        lock.lock()
                        capturedEventNames.append(contentsOf: names)
                        lock.unlock()
                    }
                }

                let options = StatsigOptions(eventLoggingEnabled: false, disableDiagnostics: true)
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues,
                    "client-api-key",
                    StatsigUser(userID: "test-user"),
                    200,
                    options: options
                )

                guard let logger = Statsig.client?.logger else {
                    fail("Failed to obtain logger"); return
                }

                Statsig.logEvent("saved_event")
                Statsig.flush()
                logger.logQueue.sync {}
                skipFrame()

                lock.lock()
                let eventsAfterFlush = capturedEventNames
                lock.unlock()
                expect(eventsAfterFlush).to(beEmpty())

                Statsig.client?.updateOptions(eventLoggingEnabled: true)
                logger.logQueue.sync {}

                expect {
                    lock.lock()
                    let hasEvent = capturedEventNames.contains("saved_event")
                    lock.unlock()
                    return hasEvent
                }.toEventually(beTrue(), timeout: .seconds(5))
            }

            it("sends new events after logging is re-enabled") {
                let lock = NSLock()
                var capturedEventNames = [String]()
                TestUtils.captureLogs { body in
                    if let events = body["events"] as? [[String: Any]] {
                        let names = events.compactMap { $0["eventName"] as? String }
                        lock.lock()
                        capturedEventNames.append(contentsOf: names)
                        lock.unlock()
                    }
                }

                let options = StatsigOptions(eventLoggingEnabled: false, disableDiagnostics: true)
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues,
                    "client-api-key",
                    StatsigUser(userID: "test-user"),
                    200,
                    options: options
                )

                guard let logger = Statsig.client?.logger else {
                    fail("Failed to obtain logger"); return
                }

                Statsig.logEvent("pre_enable_event")
                Statsig.flush()
                logger.logQueue.sync {}
                skipFrame()

                Statsig.updateOptions(eventLoggingEnabled: true)
                logger.logQueue.sync {}

                Statsig.logEvent("post_enable_event")
                Statsig.flush()
                logger.logQueue.sync {}

                expect {
                    lock.lock()
                    let hasEvent = capturedEventNames.contains("post_enable_event")
                    lock.unlock()
                    return hasEvent
                }.toEventually(beTrue(), timeout: .seconds(5))
            }
        }
    }
}
