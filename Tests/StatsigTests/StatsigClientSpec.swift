import Foundation
import Nimble
import OHHTTPStubs
import Quick
import SwiftUI

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class StatsigClientSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("initializing Statsig") {
            beforeEach {
                TestUtils.clearStorage()
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
                TestUtils.clearStorage()
            }

            it("initializes with trailing closure") {
                var callbackCalled = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)

                let client = StatsigClient(sdkKey: "client-api-key", options: opts) { _ in
                    callbackCalled = true
                }

                expect(callbackCalled).toEventually(beTrue())
                expect(client.isInitialized()).toEventually(beTrue())
            }

            it("initializes with completion param") {
                var callbackCalled = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)

                let client = StatsigClient(
                    sdkKey: "client-api-key", options: opts,
                    completion: { _ in
                        callbackCalled = true
                    })

                expect(callbackCalled).toEventually(beTrue())
                expect(client.isInitialized()).toEventually(beTrue())
            }

            it("initializes with completionWithResult param") {
                var callbackCalled = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)

                let client = StatsigClient(
                    sdkKey: "client-api-key", options: opts,
                    completionWithResult: { _ in
                        callbackCalled = true
                    })

                expect(callbackCalled).toEventually(beTrue())
                expect(client.isInitialized()).toEventually(beTrue())
            }

        }

        describe("logging events with a user override") {
            var events: [[String: Any]] = []
            var requestUser: [String: Any]?

            beforeEach {
                events = []
                requestUser = nil
                stub(condition: isPath("/v1/initialize")) { _ in
                    return HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                }
                stub(condition: isPath("/v1/rgstr")) { request in
                    let actualRequestHttpBody =
                        try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                    events = actualRequestHttpBody["events"] as? [[String: Any]] ?? []
                    requestUser = actualRequestHttpBody["user"] as? [String: Any]
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }
            }

            afterEach {
                HTTPStubs.removeAllStubs()
            }

            it("logs events using the overridden user while preserving the current user") {
                let currentUser = StatsigUser(userID: "current", email: "current@statsig.com")
                let overrideUser = StatsigUser(userID: "override", email: "override@statsig.com")

                var client: StatsigClient?
                waitUntil { done in
                    client = StatsigClient(
                        sdkKey: "client-api-key",
                        user: currentUser,
                        options: StatsigOptions(disableDiagnostics: true),
                        completion: { _ in
                            done()
                        }
                    )
                }

                client?.logEvent(
                    "override_event",
                    metadata: ["key": "value"],
                    userOverride: overrideUser
                )
                client?.logEvent("default_event", metadata: ["key": "value2"])
                client?.shutdown()

                expect(events.count).toEventually(beGreaterThanOrEqualTo(2))

                let overrideEvent = events.first(where: {
                    $0["eventName"] as? String == "override_event"
                })
                let defaultEvent = events.first(where: {
                    $0["eventName"] as? String == "default_event"
                })

                expect(overrideEvent).toEventuallyNot(beNil())
                expect(defaultEvent).toEventuallyNot(beNil())

                let overrideEventUser = overrideEvent?["user"] as? [String: Any]
                let defaultEventUser = defaultEvent?["user"] as? [String: Any]

                expect(overrideEventUser?["userID"] as? String).toEventually(
                    equal("override"))
                expect(overrideEventUser?["email"] as? String).toEventually(
                    equal("override@statsig.com"))
                expect(defaultEventUser?["userID"] as? String).toEventually(
                    equal("current"))
                expect(defaultEventUser?["email"] as? String).toEventually(
                    equal("current@statsig.com"))

                expect(requestUser?["userID"] as? String).toEventually(equal("current"))
                expect(requestUser?["email"] as? String).toEventually(equal("current@statsig.com"))
            }
        }
    }
}
