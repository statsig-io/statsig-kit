import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class ExposureLoggingSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("ExposureLogging") {
            let opts = StatsigOptions(disableDiagnostics: true)

            var logs: [[String: Any]] = []
            beforeEach {
                NetworkService.defaultEventLoggingURL = URL(
                    string: "http://ExposureLoggingSpec/v1/rgstr")
                _ = TestUtils.startWithResponseAndWait(
                    [
                        "feature_gates": [
                            "a_gate".sha256(): [
                                "value": true
                            ]
                        ],
                        "dynamic_configs": [
                            "an_experiment".sha256(): [
                                "value": ["a_bool": true]
                            ],
                            "a_config".sha256(): [
                                "value": ["a_bool": true]
                            ],
                        ],
                        "layer_configs": [
                            "a_layer".sha256(): [
                                "value": ["a_bool": true]
                            ]
                        ],
                        "time": 321,
                        "has_updates": true,
                    ], options: opts)
                Statsig.client?.logger.maxEventQueueSize = 1

                logs = []
                TestUtils.captureLogs(host: "ExposureLoggingSpec") { captured in
                    if let events = captured["events"] as? [[String: Any]] {
                        logs = events.filter({
                            ($0["eventName"] as? String) != "statsig::non_exposed_checks"
                        })
                    }
                }
            }

            afterEach {
                Statsig.client?.shutdown()
                Statsig.client = nil
                TestUtils.resetDefaultURLs()
            }

            describe("standard use") {
                it("logs gate exposures") {
                    _ = Statsig.checkGate("a_gate")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["gate"] as? String).to(equal("a_gate"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::gate_exposure"))
                }

                it("logs config exposures") {
                    _ = Statsig.getConfig("a_config")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(
                        equal("a_config"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::config_exposure"))
                }

                it("logs experiment exposures") {
                    _ = Statsig.getExperiment("an_experiment")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(
                        equal("an_experiment"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::config_exposure"))
                }

                it("logs layer exposures") {
                    let layer = Statsig.getLayer("a_layer")
                    _ = layer.getValue(forKey: "a_bool", defaultValue: false)
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(equal("a_layer"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::layer_exposure"))
                }
            }

            describe("exposure logging disabled") {
                it("does not log gate exposures") {
                    _ = Statsig.checkGateWithExposureLoggingDisabled("a_gate")
                    skipFrame()
                    expect(logs).to(haveCount(0))
                }

                it("does not log config exposures") {
                    _ = Statsig.getConfigWithExposureLoggingDisabled("a_config")
                    skipFrame()
                    expect(logs).to(haveCount(0))
                }

                it("does not log experiment exposures") {
                    _ = Statsig.getExperimentWithExposureLoggingDisabled("an_experiment")
                    skipFrame()
                    expect(logs).to(haveCount(0))
                }

                it("does not log layer exposures") {
                    let layer = Statsig.getLayerWithExposureLoggingDisabled("a_layer")
                    _ = layer.getValue(forKey: "a_bool", defaultValue: false)
                    skipFrame()
                    expect(logs).to(haveCount(0))
                }
            }

            describe("manual exposure logging via simple api") {
                it("logs a manual gate exposure") {
                    Statsig.manuallyLogGateExposure("a_gate")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["gate"] as? String).to(equal("a_gate"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::gate_exposure"))
                }

                it("logs a manual config exposure") {
                    Statsig.manuallyLogConfigExposure("a_config")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(
                        equal("a_config"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::config_exposure"))
                }

                it("logs a manual experiment exposure") {
                    Statsig.manuallyLogExperimentExposure("an_experiment")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(
                        equal("an_experiment"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::config_exposure"))
                }

                it("logs a manual layer param exposure") {
                    Statsig.manuallyLogLayerParameterExposure("a_layer", "value")
                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(equal("a_layer"))
                    expect(logs[0][jsonDict: "metadata"]?["parameterName"] as? String).to(
                        equal("value"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::layer_exposure"))
                }
            }

            describe("manual exposure logging via advanced api") {
                it("logs a manual gate exposure") {
                    let gate = Statsig.getFeatureGateWithExposureLoggingDisabled("a_gate")
                    Statsig.manuallyLogExposure(gate)

                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["gate"] as? String).to(equal("a_gate"))
                    expect(logs[0][jsonDict: "metadata"]?["gateValue"] as? String).to(equal("true"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::gate_exposure"))
                }

                it("logs a manual config exposure") {
                    let config = Statsig.getConfigWithExposureLoggingDisabled("a_config")
                    Statsig.manuallyLogExposure(config)

                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(
                        equal("a_config"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::config_exposure"))
                }

                it("logs a manual experiment exposure") {
                    let experiment = Statsig.getExperimentWithExposureLoggingDisabled(
                        "an_experiment")
                    Statsig.manuallyLogExposure(experiment)

                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(
                        equal("an_experiment"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::config_exposure"))
                }

                it("logs a manual layer param exposure") {
                    let layer = Statsig.getLayerWithExposureLoggingDisabled("a_layer")
                    Statsig.manuallyLogExposure(layer, parameterName: "value")

                    skipFrame()
                    expect(logs).to(haveCount(1))
                    expect(logs[0][jsonDict: "metadata"]?["config"] as? String).to(equal("a_layer"))
                    expect(logs[0][jsonDict: "metadata"]?["parameterName"] as? String).to(
                        equal("value"))
                    expect(logs[0][jsonDict: "metadata"]?["isManualExposure"] as? String).to(
                        equal("true"))
                    expect(logs[0]["eventName"] as? String).to(equal("statsig::layer_exposure"))
                }
            }

        }
    }
}
