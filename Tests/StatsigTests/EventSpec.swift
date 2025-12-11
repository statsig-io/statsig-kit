import Foundation
import Nimble
import Quick

@testable import Statsig

class EventSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("creating custom events") {
            it("creates basic events as expected") {
                let event = Event(
                    user: StatsigUser(), name: "purchase", disableCurrentVCLogging: false)
                expect(event.name) == "purchase"
                expect(event.value).to(beNil())
                expect(event.metadata).to(beNil())
                expect(Int(event.time / 1000)) == Int(Date().timeIntervalSince1970)
            }

            it("creates events with value and metadata as expected") {
                let event = Event(
                    user: StatsigUser(), name: "purchase", value: 1.23,
                    metadata: ["item_name": "no_ads"], disableCurrentVCLogging: false)
                expect(event.name) == "purchase"
                expect(event.value as? Double).to(equal(1.23))
                if let itemName = event.metadata?["item_name"] as? String {
                    expect(itemName) == "no_ads"
                }
                expect(Int(event.time / 1000)) == Int(Date().timeIntervalSince1970)
            }

            it("has helper functions that create gate exposure events correctly") {
                let gateExposure = Event.gateExposure(
                    user: StatsigUser(),
                    gateName: "show_coupon",
                    gateValue: true,
                    ruleID: "default",
                    secondaryExposures: [
                        ["gate": "employee", "gateValue": "true", "ruleID": "rule_id_employee"]
                    ],
                    evalDetails: EvaluationDetails(
                        source: .Network, reason: .Recognized, lcut: 123_456_789, receivedAt: 43),
                    bootstrapMetadata: BootstrapMetadata(),
                    disableCurrentVCLogging: false)

                let actualMetadata = gateExposure.metadata

                expect(gateExposure.name) == "statsig::gate_exposure"
                expect(gateExposure.value).to(beNil())
                expect(actualMetadata?["gate"] as? String) == "show_coupon"
                expect(actualMetadata?["gateValue"] as? String) == "true"
                expect(actualMetadata?["ruleID"] as? String) == "default"
                expect(actualMetadata?["reason"] as? String) == "Network:Recognized"
                expect(actualMetadata?["lcut"] as? String) == "123456789"
                expect(actualMetadata?["receivedAt"] as? String) == "43"
                if let bootstrapMetadata = actualMetadata?["bootstrapMetadata"] as? [String: Any] {
                    expect(bootstrapMetadata.isEmpty).to(beTrue())
                } else {
                    fail("bootstrapMetadata is not present or is of the wrong type")
                }
                expect(gateExposure.secondaryExposures![0]).to(
                    equal(["gate": "employee", "gateValue": "true", "ruleID": "rule_id_employee"]))
                expect(Int(gateExposure.time / 1000)) == Int(Date().timeIntervalSince1970)
            }

            it("correctly parses config exposure metadata with bootstrapMetadata") {
                let bootstrapMetadata = BootstrapMetadata(
                    generatorSDKInfo: ["version": "1.0.0"],
                    lcut: 123456,
                    user: ["userID": "user_123"]
                )

                let config = DynamicConfig(
                    configName: "my_config",
                    value: [:],
                    ruleID: "default",
                    evalDetails: EvaluationDetails(
                        source: .Network, reason: .Recognized, lcut: 123_456_789, receivedAt: 12)
                )

                let configExposure = Event.configExposure(
                    user: StatsigUser(),
                    configName: "my_config",
                    config: config,
                    bootstrapMetadata: bootstrapMetadata,
                    disableCurrentVCLogging: false
                )

                let actualMetadata = configExposure.metadata

                expect(configExposure.name) == "statsig::config_exposure"
                expect(configExposure.value).to(beNil())
                expect(actualMetadata?["config"] as? String) == "my_config"
                expect(actualMetadata?["ruleID"] as? String) == "default"
                expect(actualMetadata?["reason"] as? String) == "Network:Recognized"
                expect(actualMetadata?["lcut"] as? String) == "123456789"
                expect(actualMetadata?["receivedAt"] as? String) == "12"
                expect(actualMetadata?["rulePassed"] as? String) == "false"

                if let actualBootstrapMetadata = actualMetadata?["bootstrapMetadata"]
                    as? [String: Any]
                {
                    expect(actualBootstrapMetadata["generatorSDKInfo"] as? [String: String]) == [
                        "version": "1.0.0"
                    ]
                    expect(actualBootstrapMetadata["lcut"] as? Int) == 123456

                    // Specifically handling [String: Any] comparison for user field
                    if let actualUser = actualBootstrapMetadata["user"] as? [String: Any],
                        let userID = actualUser["userID"] as? String
                    {
                        expect(userID) == "user_123"
                    } else {
                        fail(
                            "user field in bootstrapMetadata is either missing or has an unexpected type"
                        )
                    }
                } else {
                    fail("bootstrapMetadata is not present or is of the wrong type")
                }

                expect(configExposure.secondaryExposures).to(equal([]))
                expect(Int(configExposure.time / 1000)) == Int(Date().timeIntervalSince1970)
            }

            it("has helper functions that create internal events correctly") {
                let internalEvent = Event.statsigInternalEvent(
                    user: StatsigUser(),
                    name: "network_failure",
                    value: 10,
                    metadata: nil,
                    disableCurrentVCLogging: false)

                expect(internalEvent.name) == "statsig::network_failure"
                expect(internalEvent.value as? Int).to(equal(10))
                expect(internalEvent.metadata).to(beNil())
                expect(Int(internalEvent.time / 1000)) == Int(Date().timeIntervalSince1970)
            }
        }
    }
}
