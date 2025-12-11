import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

typealias Map = [String: AnyHashable]

class LocalOverridesSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("LocalOverrides") {
            beforeEach {
                TestUtils.clearStorage()

                _ = TestUtils.startWithResponseAndWait([
                    "feature_gates": [],
                    "dynamic_configs": [],
                    "layer_configs": [],
                    "has_updates": true,
                ])
            }

            afterEach {
                Statsig.client?.shutdown()
                Statsig.client = nil
            }

            describe("gate overrides") {
                it("returns overridden gate values") {
                    Statsig.overrideGate("overridden_gate", value: true)
                    expect(Statsig.checkGate("overridden_gate")).to(beTrue())
                }

                it("clears overridden gate values") {
                    Statsig.overrideGate("overridden_gate", value: true)
                    Statsig.removeOverride("overridden_gate")
                    expect(Statsig.checkGate("overridden_gate")).to(beFalse())
                }
            }

            describe("config overrides") {
                it("returns overridden config values") {
                    Statsig.overrideConfig("overridden_config", value: ["key": "value"])
                    expect(Statsig.getConfig("overridden_config").value as? Map).to(
                        equal(["key": "value"] as Map))
                }

                it("clears overridden config values") {
                    Statsig.overrideConfig("overridden_config", value: ["key": "value"])
                    Statsig.removeOverride("overridden_config")
                    expect(Statsig.getConfig("overridden_config").value as? Map).to(
                        equal([:] as? Map))
                }
            }

            describe("layer overrides") {
                it("returns overridden layer values") {
                    Statsig.overrideLayer("overridden_layer", value: ["key": "value"])
                    let layer = Statsig.getLayer("overridden_layer")
                    expect(layer.getValue(forKey: "key", defaultValue: "err")).to(equal("value"))
                }

                it("clears overridden layer values") {
                    Statsig.overrideLayer("overridden_layer", value: ["key": "value"])
                    Statsig.removeOverride("overridden_layer")

                    let layer = Statsig.getLayer("overridden_layer")
                    expect(layer.getValue(forKey: "key", defaultValue: "default")).to(
                        equal("default"))
                }
            }

            describe("parameter store overrides") {
                it("returns overridden parameter store values") {
                    Statsig.overrideParamStore("overridden_param_store", value: ["key": "value"])
                    let store = Statsig.getParameterStore("overridden_param_store")
                    expect(store.getValue(forKey: "key", defaultValue: "default")).to(
                        equal("value"))
                }

                it("clears overridden parameter store values") {
                    Statsig.overrideParamStore("overridden_param_store", value: ["key": "value"])
                    Statsig.removeOverride("overridden_param_store")
                    expect(
                        Statsig.getParameterStore("overridden_param_store").getValue(
                            forKey: "key", defaultValue: "default")
                    ).to(equal("default"))
                }
            }

            describe("clearing all overrides") {
                it("clears all") {
                    Statsig.overrideGate("overridden_gate", value: true)
                    Statsig.overrideConfig("overridden_config", value: ["key": "value"])
                    Statsig.overrideLayer("overridden_layer", value: ["key": "value"])

                    Statsig.removeAllOverrides()

                    expect(Statsig.checkGate("overridden_gate")).to(beFalse())
                    expect(Statsig.getConfig("overridden_config").value as? Map).to(
                        equal([:] as? Map))
                    let layer = Statsig.getLayer("overridden_layer")
                    expect(layer.getValue(forKey: "key", defaultValue: "default")).to(
                        equal("default"))
                }
            }
        }
    }
}
