import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class EvaluationCallbackSpec: BaseSpec {
    override func spec() {
        super.spec()

        let baseResponse: [String: Any] = [
            "feature_gates": [
                "a_gate": [
                    "value": true
                ]
            ],
            "dynamic_configs": [],
            "hash_used": "none",
            "layer_configs": [],
            "time": 123,
            "has_updates": true,
        ]

        describe("EvaluationCallback") {
            var gateNameResult: String? = nil
            var configNameResult: String? = nil
            var experimentNameResult: String? = nil
            var layerNameResult: String? = nil
            var paramStoreNameResult: String? = nil

            beforeEach {
                // Setup Event Capture
                stub(condition: isPath("/v1/rgstr")) { request in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                // Initialize Client Instance
                stub(condition: isPath("/v1/initialize")) { _ in
                    HTTPStubsResponse(jsonObject: baseResponse, statusCode: 200, headers: nil)
                }

                func callback(data: StatsigOptions.EvaluationCallbackData) {
                    switch data {
                    case .gate(let gate):
                        gateNameResult = gate.name
                    case .config(let config):
                        configNameResult = config.name
                    case .experiment(let exp):
                        experimentNameResult = exp.name
                    case .layer(let layer):
                        layerNameResult = layer.name
                    case .parameterStore(let paramStore):
                        paramStoreNameResult = paramStore.name
                    }
                }

                let opts = StatsigOptions(evaluationCallback: callback)
                Statsig.initialize(sdkKey: "client-api-key", options: opts)
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
            }

            it("gets different gate results") {
                _ = Statsig.checkGate("a_gate")
                expect(gateNameResult).to(equal("a_gate"))
                _ = Statsig.checkGateWithExposureLoggingDisabled("b_gate")
                expect(gateNameResult).to(equal("b_gate"))
            }

            it("works with configs") {
                _ = Statsig.getConfig("a_config")
                expect(configNameResult).to(equal("a_config"))
                _ = Statsig.getConfigWithExposureLoggingDisabled("b_config")
                expect(configNameResult).to(equal("b_config"))
            }

            it("works with experiments") {
                _ = Statsig.getExperiment("a_exp")
                expect(experimentNameResult).to(equal("a_exp"))
                _ = Statsig.getExperimentWithExposureLoggingDisabled("b_exp")
                expect(experimentNameResult).to(equal("b_exp"))
            }

            it("works with layers") {
                _ = Statsig.getLayer("a_layer")
                expect(layerNameResult).to(equal("a_layer"))
                _ = Statsig.getLayerWithExposureLoggingDisabled("b_layer")
                expect(layerNameResult).to(equal("b_layer"))
            }

            it("works with parameter stores") {
                _ = Statsig.getParameterStore("a_param_store")
                expect(paramStoreNameResult).to(equal("a_param_store"))
                _ = Statsig.getParameterStoreWithExposureLoggingDisabled("b_param_store_layer")
                expect(paramStoreNameResult).to(equal("b_param_store_layer"))
            }
        }
    }
}
