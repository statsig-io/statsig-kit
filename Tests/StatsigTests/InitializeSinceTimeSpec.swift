import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class InitializeSinceTimeSpec: BaseSpec {
    let response: [String: Any] = [
        "feature_gates": [
            "a_gate".sha256(): [
                "value": true
            ]
        ],
        "dynamic_configs": [
            "a_config".sha256(): [
                "value": ["a_bool": true]
            ]
        ],
        "layer_configs": [],
        "time": 123,
        "has_updates": true,
    ]

    private func shutdownStatsig() {
        Statsig.client?.shutdown()
        Statsig.client = nil
    }

    override func spec() {
        super.spec()

        describe("InitializeSinceTime") {
            beforeEach {
                TestUtils.clearStorage()
            }

            afterEach {
                self.shutdownStatsig()
            }

            it("defaults sinceTime to zero") {
                let req = TestUtils.startWithResponseAndWait(self.response)
                let data = req!.statsig_body!
                expect(data["sinceTime"] as? Double).to(equal(0.0 as Double))
            }

            it("passes sinceTime on repeated start ups") {
                _ = TestUtils.startWithResponseAndWait(self.response)
                self.shutdownStatsig()

                let req = TestUtils.startWithResponseAndWait(self.response)
                let data = req!.statsig_body!
                expect(data["sinceTime"] as? Double).to(equal(123.0 as Double))
            }

            it("uses cached value when 204 is returned") {
                _ = TestUtils.startWithResponseAndWait(self.response)
                self.shutdownStatsig()

                _ = TestUtils.startWithStatusAndWait(204)
                expect(Statsig.checkGate("a_gate")).to(beTrue())
            }

            it("uses cached value when 204 with has_updates=false is returned") {
                _ = TestUtils.startWithResponseAndWait(self.response)
                self.shutdownStatsig()

                _ = TestUtils.startWithResponseAndWait(
                    ["has_updates": false], "client-api-key", nil, 204)
                expect(Statsig.checkGate("a_gate")).to(beTrue())
            }

            it("uses cached value when 200 with has_updates=false is returned") {
                _ = TestUtils.startWithResponseAndWait(self.response)
                self.shutdownStatsig()

                _ = TestUtils.startWithResponseAndWait(
                    ["has_updates": false], "client-api-key", nil, 200)
                expect(Statsig.checkGate("a_gate")).to(beTrue())
            }

            it("updates values when initialized a second time") {
                _ = TestUtils.startWithResponseAndWait(self.response)
                self.shutdownStatsig()

                let secondResponse = self.response.merging([
                    "feature_gates": [
                        "b_gate".sha256(): [
                            "value": true
                        ]
                    ]
                ]) { $1 }
                _ = TestUtils.startWithResponseAndWait(secondResponse)
                expect(Statsig.checkGate("a_gate")).to(beFalse())
                expect(Statsig.checkGate("b_gate")).to(beTrue())
            }

            it("invalidates the cache key when a user object changes") {
                let firstUser = StatsigUser(userID: "a-user", email: "a-user@gmail.com")
                let firstRequest = TestUtils.startWithResponseAndWait(
                    self.response, "client-api-key", firstUser)
                let firstBody = firstRequest?.statsig_body as! [String: AnyHashable]

                let secondUser = StatsigUser(userID: "a-user", email: "a-user@live.com")
                let secondRequest = TestUtils.startWithResponseAndWait(
                    self.response, "client-api-key", secondUser)
                let secondBody = secondRequest?.statsig_body as! [String: AnyHashable]

                expect(firstBody["sinceTime"]).to(equal(0))
                expect(secondBody["sinceTime"])
                    .to(
                        equal(0),
                        description:
                            "Should fail to find a cached sinceTime because the email changed")
            }

            it("sets the init reason to NetworkNotModified") {
                _ = TestUtils.startWithResponseAndWait(self.response)
                self.shutdownStatsig()

                _ = TestUtils.startWithResponseAndWait(
                    ["has_updates": false], "client-api-key", nil, 200)

                let config = Statsig.getConfig("a_config")
                expect(config.evaluationDetails.reason).to(equal(.Recognized))
            }
        }
    }
}
