import Foundation
import Nimble
import OHHTTPStubs
import Quick
import SwiftUI

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class SDKKeySpec: BaseSpec {
    static let mockUserValues: [String: Any] = [
        "feature_gates": [
            "gate_name_1".sha256(): [
                "value": false,
                "rule_id": "rule_id_1",
                "secondary_exposures": [
                    ["gate": "employee", "gateValue": "true", "ruleID": "rule_id_employee"]
                ],
            ],
            "gate_name_2".sha256(): ["value": true, "rule_id": "rule_id_2"],
        ],
        "dynamic_configs": [
            "config".sha256(): DynamicConfigSpec.TestMixedConfig
        ],
        "layer_configs": [
            "allocated_layer".sha256(): DynamicConfigSpec
                .TestMixedConfig
                .merging(["allocated_experiment_name": "config".sha256()]) { (_, new) in new },
            "unallocated_layer".sha256(): DynamicConfigSpec
                .TestMixedConfig,
        ],
        "has_updates": true,
    ]

    override func spec() {
        super.spec()

        describe("SDK Keys") {
            beforeEach {
                TestUtils.clearStorage()
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
                TestUtils.clearStorage()
            }

            it("works when provided invalid SDK key by returning default value") {
                stub(condition: isHost(ApiHost)) { _ in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 403, headers: nil)
                }

                var errorMessage: String?
                var gate: Bool?
                var config: DynamicConfig?
                waitUntil { done in
                    let opts = StatsigOptions(disableDiagnostics: true)
                    Statsig.initialize(sdkKey: "invalid_sdk_key", options: opts) { err in
                        errorMessage = err?.message
                        gate = Statsig.checkGate("show_coupon")
                        config = Statsig.getConfig("my_config")
                        done()
                    }
                }

                expect(errorMessage).toEventually(contain("403"))
                expect(gate).toEventually(beFalse())
                expect(NSDictionary(dictionary: config!.value)).toEventually(
                    equal(NSDictionary(dictionary: [:])))
                expect(config!.evaluationDetails.reason).toEventually(equal(.Unrecognized))
            }

            it("works when provided server secret by returning default value") {
                var errorCode: StatsigClientErrorCode?
                var gate: Bool?
                var config: DynamicConfig?
                Statsig.initialize(sdkKey: "secret-key") { err in
                    errorCode = err?.code
                    gate = Statsig.checkGate("show_coupon")
                    config = Statsig.getConfig("my_config")
                }
                expect(errorCode).toEventually(equal(StatsigClientErrorCode.invalidClientSDKKey))
                expect(gate).toEventually(beFalse())
                expect(NSDictionary(dictionary: config!.value)).toEventually(
                    equal(NSDictionary(dictionary: [:])))
                expect(config!.evaluationDetails.source).toEventually(equal(.Uninitialized))
            }
        }
    }
}
