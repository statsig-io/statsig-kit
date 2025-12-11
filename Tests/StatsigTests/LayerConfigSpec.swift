import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

fileprivate struct Data {
    static let GateKey = "gate"
    static let HashGateKey = GateKey.sha256()
    static let FeatureGates = [
        HashGateKey: ["value": true, "rule_id": "rule_id_2"]
    ]

    static let ConfigKey = "config"
    static let HashConfigKey = ConfigKey.sha256()

    static let AnotherConfigKey = "another_config"
    static let HashAnotherConfigKey = AnotherConfigKey.sha256()

    static let DeviceBasedConfigKey = "device_based_config"
    static let HashDeviceBasedConfigKey = DeviceBasedConfigKey.sha256()

    static let DynamicConfigs = [
        HashConfigKey: [
            "name": HashConfigKey,
            "rule_id": "default",
            "value": ["key": "value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
        ],
        HashAnotherConfigKey: [
            "name": HashAnotherConfigKey,
            "rule_id": "default",
            "value": ["key": "another_value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
        ],
        HashDeviceBasedConfigKey: [
            "name": HashDeviceBasedConfigKey,
            "rule_id": "default",
            "value": ["key": "device_based_value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
            "is_device_based": true,
        ],
    ]

    static let TestMixedConfigValue: [String: Any] = [
        "str": "string",
        "bool": true,
        "double": 3.14,
        "int": 3,
        "strArray": ["1", "2"],
        "mixedArray": [1, "2"],
        "dict": ["key": "value"],
        "mixedDict": [
            "keyStr": "string",
            "keyInt": 2,
            "keyArr": [1, 2],
            "keyDouble": 1.23,
            "keyDict": ["k": "v"],
        ],
    ]

    static let LayerConfigWithExperimentKey = "layer_with_exp"
    static let HashLayerConfigWithExperimentKey = LayerConfigWithExperimentKey.sha256()

    static let LayerConfigWithoutExperimentKey = "layer_without_exp"
    static let HashLayerConfigWithoutExperimentKey = LayerConfigWithoutExperimentKey.sha256()

    static let LayerConfigs: [String: Any] = [
        HashLayerConfigWithExperimentKey: [
            "name": HashLayerConfigWithExperimentKey,
            "rule_id": "default",
            "value": ["key": "value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
            "allocated_experiment_name": HashConfigKey,
        ],
        HashLayerConfigWithoutExperimentKey: [
            "name": HashLayerConfigWithExperimentKey,
            "rule_id": "default",
            "value": ["key": "another_value"],
            "is_user_in_experiment": true,
            "is_experiment_active": true,
        ],
    ]

    static let CacheValues: [String: Any] = [
        "dynamic_configs": DynamicConfigs,
        "feature_gates": FeatureGates,
        "layer_configs": LayerConfigs,
        "has_updates": true,
    ]

    static let StickyValues = [
        HashConfigKey: [
            "rule_id": "sticky",
            "value": ["key": "value_sticky"],
        ]
    ]
}

class LayerConfigSpec: BaseSpec {

    override func spec() {
        super.spec()

        describe("using getLayerConfig") {
            var client: StatsigClient!
            var store: InternalStore!

            beforeEach {
                TestUtils.clearStorage()

                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                waitUntil { done in
                    let opts = StatsigOptions(disableDiagnostics: true)
                    client = StatsigClient(
                        sdkKey: "", user: nil, options: opts,
                        completion: { err in
                            done()
                        })
                }

                let options = StatsigOptions()
                let user = StatsigUser(userID: "dloomb")
                store = InternalStore("", user, options: options)

                let cacheKey = UserCacheKey.from(options, user, "")
                store.cache.saveValues(Data.CacheValues, cacheKey, user.getFullUserHash())
            }

            it("returns the experiment values") {
                let config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: false)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                let another = store.getLayer(
                    client: client, forName: Data.LayerConfigWithoutExperimentKey,
                    keepDeviceValue: false)
                expect(another.getValue(forKey: "key", defaultValue: "ERR")).to(
                    equal("another_value"))
            }

            it("should return a sticky value") {
                var config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: true)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                var updatedValues: [String: Any] = Data.CacheValues
                updatedValues[jsonDict: "dynamic_configs"]?[jsonDict: Data.HashConfigKey]?[
                    "is_user_in_experiment"] = false

                let user = StatsigUser(userID: "dloomb")
                store = InternalStore("", user, options: StatsigOptions())  // reload the cache, and user is no longer in the experiment, but value should stick because experiment is active

                waitUntil { done in
                    store.saveValues(
                        updatedValues, store.cache.userCacheKey, user.getFullUserHash()
                    ) {
                        done()
                    }
                }

                config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: true)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                updatedValues[jsonDict: "layer_configs"]?[
                    jsonDict: Data.HashLayerConfigWithExperimentKey] = [
                        "name": Data.HashLayerConfigWithExperimentKey,
                        "rule_id": "default",
                        "value": ["key": "another_value"],
                        "is_user_in_experiment": true,
                        "is_experiment_active": true,
                        "allocated_experiment_name": "completely_different_exp",
                    ]

                // reload the cache, and user is allocated to a different experiment,
                // but should still get same value because previous experiment is still active
                store = InternalStore("", user, options: StatsigOptions())

                waitUntil { done in
                    store.saveValues(
                        updatedValues, store.cache.userCacheKey, user.getFullUserHash()
                    ) {
                        done()
                    }
                }

                config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: true)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                updatedValues[jsonDict: "dynamic_configs"]?[jsonDict: Data.HashConfigKey]?[
                    "is_experiment_active"] = false
                // reload the cache, and previous experiment is no longer active, so should get new value
                store = InternalStore("", StatsigUser(userID: "dloomb"), options: StatsigOptions())

                waitUntil { done in
                    store.saveValues(
                        updatedValues, store.cache.userCacheKey, user.getFullUserHash()
                    ) {
                        done()
                    }
                }

                config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: true)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(
                    equal("another_value"))
            }

            it("should wipe sticky value when keepDeviceValue is false") {
                var config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: true)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(equal("value"))

                var updatedValues: [String: Any] = Data.CacheValues
                updatedValues[jsonDict: "layer_configs"]?[
                    jsonDict: Data.HashLayerConfigWithExperimentKey] = [
                        "name": Data.HashLayerConfigWithExperimentKey,
                        "rule_id": "default",
                        "value": ["key": "another_value"],
                        "is_user_in_experiment": true,
                        "is_experiment_active": true,
                        "allocated_experiment_name": Data.AnotherConfigKey,
                    ]

                let user = StatsigUser(userID: "dloomb")
                store = InternalStore("", user, options: StatsigOptions())
                waitUntil { done in
                    store.saveValues(
                        updatedValues, store.cache.userCacheKey, user.getFullUserHash()
                    ) {
                        done()
                    }
                }
                config = store.getLayer(
                    client: client, forName: Data.LayerConfigWithExperimentKey,
                    keepDeviceValue: false)
                expect(config.getValue(forKey: "key", defaultValue: "ERR")).to(
                    equal("another_value"))
            }

            it("returns the default value for mismatched types") {
                let layer = Layer(
                    client: client, name: "a_layer",
                    value: [
                        "str": "string",
                        "bool": true,
                        "double": 3.14,
                        "int": 3,
                        "strArray": ["1", "2"],
                        "mixedArray": [1, "2"],
                        "dict": ["key": "value"],
                        "mixedDict": [
                            "keyStr": "string",
                            "keyInt": 2,
                            "keyArr": [1, 2],
                            "keyDouble": 1.23,
                            "keyDict": ["k": "v"],
                        ],
                    ], ruleID: "", groupName: nil, evalDetails: .init(source: .Cache))
                expect(layer.getValue(forKey: "str", defaultValue: 1)) == 1
                expect(layer.getValue(forKey: "str", defaultValue: true)) == true

                expect(layer.getValue(forKey: "bool", defaultValue: "false")) == "false"
                expect(layer.getValue(forKey: "bool", defaultValue: 0)) == 0

                expect(layer.getValue(forKey: "double", defaultValue: 1)) == 1
                expect(layer.getValue(forKey: "double", defaultValue: "str")) == "str"

                expect(layer.getValue(forKey: "int", defaultValue: 1.0)) == 1.0
                expect(layer.getValue(forKey: "int", defaultValue: "1")) == "1"

                expect(layer.getValue(forKey: "strArray", defaultValue: [1, 2, 3])) == [1, 2, 3]

                expect(layer.getValue(forKey: "mixedArray", defaultValue: [1, 2, 3])) == [1, 2, 3]

                expect(layer.getValue(forKey: "dict", defaultValue: ["key": 3])) == ["key": 3]

                expect(layer.getValue(forKey: "mixedDict", defaultValue: ["key": "value"])) == [
                    "key": "value"
                ]
            }

            it("returns the default value for non-existent key") {
                let layer = Layer(
                    client: client, name: "a_layer", value: [:], ruleID: "", groupName: nil,
                    evalDetails: .uninitialized())
                expect(layer.getValue(forKey: "wrong_key", defaultValue: 1)) == 1
                expect(layer.getValue(forKey: "wrong_key", defaultValue: true)) == true
                expect(layer.getValue(forKey: "wrong_key", defaultValue: "false")) == "false"
                expect(layer.getValue(forKey: "wrong_key", defaultValue: 1.23)) == 1.23
                expect(layer.getValue(forKey: "wrong_key", defaultValue: [1, 2, 3])) == [1, 2, 3]
                expect(layer.getValue(forKey: "wrong_key", defaultValue: ["key": 3])) == ["key": 3]
                expect(layer.getValue(forKey: "wrong_key", defaultValue: ["key": "value"])) == [
                    "key": "value"
                ]
            }

            describe("not using defaultValue") {
                var layer: Layer!

                beforeEach {
                    layer = Layer(
                        client: client,
                        name: "a_layer",
                        value: Data.TestMixedConfigValue,
                        ruleID: "default",
                        groupName: nil,
                        evalDetails: .init(source: .Network))
                }

                it("returns values with different type specifications") {
                    // Inferrable
                    expect(layer.getValue(forKey: "str")) == "string"
                    // Explicit type definition
                    let a: String? = layer.getValue(forKey: "str")
                    expect(a) == "string"
                    // Casting
                    let b = layer.getValue(forKey: "str") as String?
                    expect(b) == "string"
                }

                it("returns nil when the type doesn't match") {
                    // Explicit type definition
                    let a: Int? = layer.getValue(forKey: "str")
                    expect(a) == nil
                    // Casting
                    let b = layer.getValue(forKey: "str") as Int?
                    expect(b) == nil
                }

                it("returns nil when the key is unknown") {
                    // Explicit type definition
                    let a: String? = layer.getValue(forKey: "wrong_key")
                    expect(a) == nil
                    // Casting
                    let b = layer.getValue(forKey: "wrong_key") as String?
                    expect(b) == nil
                }

                it("returns nil when the layer doesn't exist") {
                    let dummy = Layer(
                        client: client,
                        name: "dummy",
                        value: [:],
                        ruleID: "",
                        groupName: nil,
                        evalDetails: .init(source: .Network))

                    // Explicit type definition
                    let a: String? = dummy.getValue(forKey: "str")
                    expect(a) == nil
                    // Casting
                    let b = dummy.getValue(forKey: "str") as String?
                    expect(b) == nil
                }

                it("returns values of every type") {
                    expect(layer.getValue(forKey: "str")) == "string"
                    expect(layer.getValue(forKey: "bool")) == true
                    expect(layer.getValue(forKey: "double")) == 3.14
                    expect(layer.getValue(forKey: "int")) == 3
                    expect(layer.getValue(forKey: "strArray")) == ["1", "2"]

                    expect(layer.evaluationDetails.source).to(equal(.Network))

                    let mixedArray: [any StatsigDynamicConfigValue]? = layer.getValue(
                        forKey: "mixedArray")
                    expect(mixedArray?.count) == 2
                    expect(mixedArray?[0] as? Int) == 1
                    expect(mixedArray?[1] as? String) == "2"

                    let dict: [String: String]? = layer.getValue(forKey: "dict")
                    expect(dict?.count) == 1
                    expect(dict?["key"]) == "value"

                    let mixedDict: [String: any StatsigDynamicConfigValue]? = layer.getValue(
                        forKey: "mixedDict")
                    expect(mixedDict?.count) == 5
                    expect(mixedDict?["keyStr"] as? String) == "string"
                    expect(mixedDict?["keyInt"] as? Int) == 2
                    expect(mixedDict?["keyArr"] as? [Int]) == [1, 2]
                    expect(mixedDict?["keyDouble"] as? Double) == 1.23
                    expect(mixedDict?["keyDict"] as? [String: String]) == ["k": "v"]

                    expect(layer.ruleID) == "default"
                }
            }
        }
    }
}
