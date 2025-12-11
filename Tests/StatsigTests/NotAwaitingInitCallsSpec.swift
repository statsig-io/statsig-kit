import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class NotAwaitingInitCallsSpec: BaseSpec {
    override func spec() {
        super.spec()

        let options = StatsigOptions()
        let userA = StatsigUser(userID: "user-a", customIDs: ["workID": "employee-a"])
        let userB = StatsigUser(userID: "user-b", customIDs: ["workID": "employee-b"])

        describe("Not Awaiting Init Calls") {

            beforeEach {
                NetworkService.defaultInitializationURL = URL(
                    string: "http://NotAwaitingInitCallsSpec/v1/initialize")

                TestUtils.clearStorage()

                stub(condition: isHost("NotAwaitingInitCallsSpec")) { req in
                    if (req.url?.absoluteString.contains("/initialize") ?? false) == false {
                        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                    }

                    let body = TestUtils.getBody(fromRequest: req)
                    let userId = body[jsonDict: "user"]?["userID"] as? String
                    if userId == "user-a" {
                        return HTTPStubsResponse(
                            jsonObject: TestUtils.makeInitializeResponse("user_a_value"),
                            statusCode: 200, headers: nil)
                    }

                    if userId == "user-b" {
                        return HTTPStubsResponse(
                            jsonObject: TestUtils.makeInitializeResponse("user_b_value"),
                            statusCode: 200, headers: nil
                        ).responseTime(0.1)
                    }

                    return HTTPStubsResponse(jsonObject: [:], statusCode: 500, headers: nil)
                }
            }

            afterEach {
                TestUtils.resetDefaultURLs()
            }

            it("gets the expected values") {
                var isInitialized = false

                expect(Statsig.client).toEventually(beNil(), timeout: .seconds(1000))

                Statsig.initialize(sdkKey: "client-key", user: userA, options: options) { err in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                        isInitialized = true
                    }
                }

                expect(
                    Statsig.getConfig("a_config").getValue(forKey: "key", defaultValue: "fallback")
                ).to(equal("fallback"))

                expect(isInitialized).toEventually(beTrue())

                expect(
                    Statsig.getConfig("a_config").getValue(forKey: "key", defaultValue: "fallback")
                ).to(equal("user_a_value"))

                var isUpdated = false
                Statsig.updateUserWithResult(userB) { err in
                    isUpdated = true
                }

                expect(
                    Statsig.getConfig("a_config").getValue(forKey: "key", defaultValue: "fallback")
                ).to(equal("fallback"))

                expect(isUpdated).toEventually(beTrue())

                expect(
                    Statsig.getConfig("a_config").getValue(forKey: "key", defaultValue: "fallback")
                ).to(equal("user_b_value"))
            }
        }
    }
}
