import Foundation
import Nimble
import OHHTTPStubs
import Quick
import SwiftUI

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class StatsigSpec: BaseSpec {
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

    static let configKey = "config"
    static let hashConfigKey = configKey.sha256()
    static let mockUpdatedUserValues: [String: Any] = [
        "dynamic_configs": [
            hashConfigKey: [
                "rule_id": "default",
                "value": ["key": "new_value"],
                "is_user_in_experiment": true,
                "is_experiment_active": true,
            ]
        ],
        "feature_gates": [
            "new_gate_name_1".sha256(): [
                "value": true,
                "rule_id": "rule_id_1",
                "secondary_exposures": [
                    ["gate": "employee", "gateValue": "true", "ruleID": "rule_id_employee"]
                ],
            ],
            "new_gate_name_2".sha256(): ["value": true, "rule_id": "rule_id_2"],
        ],
        "has_updates": true,
    ]

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
                TestUtils.resetDefaultURLs()
            }

            let gateName1 = "gate_name_1"
            let gateName2 = "gate_name_2"
            let nonExistentGateName = "gate_name_3"

            let configName = "config"
            let nonExistentConfigName = "non_existent_config"

            it("only makes 1 network request if start() is called multiple times") {
                var requests = []
                stub(condition: isHost(ApiHost)) { req in
                    if req.url?.absoluteString.contains("/initialize") as? Bool == true {
                        requests.append(req)
                    }

                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)
                Statsig.initialize(sdkKey: "client-api-key", options: opts)
                Statsig.initialize(sdkKey: "client-api-key", options: opts)
                Statsig.initialize(sdkKey: "client-api-key", options: opts)

                expect(requests.count).toEventually(equal(1))
            }

            it("make only 1 network request in 0.1 seconds when enableAutoValueUpdate is FALSE") {
                var requestCount = 0
                var lastSyncTime: Double = 0
                let now = Date().timeIntervalSince1970

                stub(condition: isHost("api.statsig.enableAutoValueUpdateTest")) { request in
                    requestCount += 1

                    let httpBody =
                        try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                    lastSyncTime = httpBody["lastSyncTimeForUser"] as? Double ?? 0

                    return HTTPStubsResponse(
                        jsonObject: ["time": now * 1000], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(
                    enableAutoValueUpdate: false,
                    autoValueUpdateIntervalSec: 0.1,
                    disableDiagnostics: true
                )
                NetworkService.defaultInitializationURL = URL(
                    string: "http://api.statsig.enableAutoValueUpdateTest/v1/initialize")
                Statsig.initialize(sdkKey: "client-api-key", options: opts)

                // first request, "lastSyncTimeForUser" field should not be present in the request body
                expect(requestCount).toEventually(equal(1), timeout: .milliseconds(200))
                expect(lastSyncTime).to(equal(0))
            }

            it(
                "makes 2 network requests in 0.1 seconds and updates internal store's updatedTime correctly each time when enableAutoValueUpdate is TRUE"
            ) {
                var requestCount = 0
                var lastSyncTime: UInt64 = 0
                let dummyLcut = Time.now()

                let opts = StatsigOptions(
                    enableAutoValueUpdate: true,
                    autoValueUpdateIntervalSec: 0.1,
                    disableDiagnostics: true
                )
                NetworkService.defaultInitializationURL = URL(
                    string: "http://StatsigSpec.enableAutoValueUpdateEQtrue/v1/initialize")

                var requestExpectation = self.expectation(description: "Request Made Once")
                stub(condition: isHost("StatsigSpec.enableAutoValueUpdateEQtrue")) { request in
                    requestCount += 1

                    let httpBody = request.statsig_body ?? [:]
                    lastSyncTime = httpBody["lastSyncTimeForUser"] as? UInt64 ?? 0

                    requestExpectation.fulfill()
                    return HTTPStubsResponse(
                        jsonObject: ["time": dummyLcut, "has_updates": true], statusCode: 200,
                        headers: nil)
                }

                Statsig.initialize(sdkKey: "client-api-key", options: opts)

                self.wait(for: [requestExpectation], timeout: 0.05)
                requestExpectation = self.expectation(description: "Request Made Twice")

                // first request, "lastSyncTimeForUser" field should not be present in the request body
                expect(requestCount).to(equal(1))
                expect(lastSyncTime).to(equal(0))

                self.wait(for: [requestExpectation], timeout: 1)
                // second request, "lastSyncTimeForUser" field should be the time when the first request was sent
                expect(requestCount).to(equal(2))
                expect(lastSyncTime).to(equal(dummyLcut))
            }

            it("values are updated when update user with values called") {
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues, "client-api-key", StatsigUser(userID: "whd"))

                var config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal(""))

                expect(Statsig.checkGate("new_gate_name_1")).to(beFalse())
                expect(Statsig.checkGate("new_gate_name_2")).to(beFalse())

                waitUntil { done in
                    Statsig.updateUserWithResult(
                        StatsigUser(userID: "whd", customIDs: ["companyID": "statsig"]),
                        values: StatsigSpec.mockUpdatedUserValues
                    ) { _ in
                        done()
                    }
                }

                expect(Statsig.checkGate("new_gate_name_1")).to(beTrue())
                expect(Statsig.checkGate("new_gate_name_2")).to(beTrue())

                config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal("new_value"))
            }

            it("values are updated when update user with values called with the deprecated method")
            {
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues, "client-api-key", StatsigUser(userID: "whd"))

                var config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal(""))

                expect(Statsig.checkGate("new_gate_name_1")).to(beFalse())
                expect(Statsig.checkGate("new_gate_name_2")).to(beFalse())

                waitUntil { done in
                    Statsig.updateUser(
                        StatsigUser(userID: "whd", customIDs: ["companyID": "statsig"]),
                        values: StatsigSpec.mockUpdatedUserValues
                    ) { _ in
                        done()
                    }
                }

                expect(Statsig.checkGate("new_gate_name_1")).to(beTrue())
                expect(Statsig.checkGate("new_gate_name_2")).to(beTrue())

                config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal("new_value"))
            }

            it("values are updated for the current user if manual refresh triggered") {
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues, "client-api-key", StatsigUser(userID: "whd"))

                var config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal(""))

                expect(Statsig.checkGate("new_gate_name_1")).to(beFalse())
                expect(Statsig.checkGate("new_gate_name_2")).to(beFalse())

                stub(condition: isHost(ApiHost)) { request in
                    return HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUpdatedUserValues, statusCode: 200, headers: nil
                    )
                }

                waitUntil { done in
                    Statsig.refreshCacheWithResult { _ in
                        done()
                    }
                }

                expect(Statsig.checkGate("new_gate_name_1")).to(beTrue())
                expect(Statsig.checkGate("new_gate_name_2")).to(beTrue())

                config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal("new_value"))
            }

            it(
                "values are updated for the current user if manual refresh triggered with the deprecated method"
            ) {
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues, "client-api-key", StatsigUser(userID: "whd"))

                var config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal(""))

                expect(Statsig.checkGate("new_gate_name_1")).to(beFalse())
                expect(Statsig.checkGate("new_gate_name_2")).to(beFalse())

                stub(condition: isHost(ApiHost)) { request in
                    return HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUpdatedUserValues, statusCode: 200, headers: nil
                    )
                }

                waitUntil { done in
                    Statsig.refreshCache { _ in
                        done()
                    }
                }

                expect(Statsig.checkGate("new_gate_name_1")).to(beTrue())
                expect(Statsig.checkGate("new_gate_name_2")).to(beTrue())

                config = Statsig.getConfig(StatsigSpec.configKey)
                expect(config.getValue(forKey: "key", defaultValue: "")).to(equal("new_value"))
            }

            it("works with local cache with different user cache keys") {
                _ = TestUtils.startWithResponseAndWait(
                    StatsigSpec.mockUserValues, "client-api-key", StatsigUser(userID: "jkw"))

                let gateName = "gate_name_2"

                // gate should be true, using network response;
                expect(Statsig.checkGate(gateName)).to(beTrue())

                // the values are now cached for the first user. Now test when network is not available, and cache for the first user should NOT be used
                stub(condition: isHost(ApiHost)) { _ in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 403, headers: nil)
                }

                waitUntil { done in
                    Statsig.updateUserWithResult(
                        StatsigUser(userID: "jkw", customIDs: ["companyID": "statsig"])
                    ) { _ in
                        done()
                    }
                }
                // should only return the default value, because cache key, which uses userID AND customIDs, have changed
                expect(Statsig.checkGate(gateName)).to(beFalse())

                waitUntil { done in
                    Statsig.updateUserWithResult(StatsigUser()) { _ in
                        done()
                    }
                }
                expect(Statsig.checkGate(gateName)).to(beFalse())

                // back to the original user, cache should now be used
                waitUntil { done in
                    Statsig.updateUserWithResult(StatsigUser(userID: "jkw")) { _ in
                        done()
                    }
                }
                expect(Statsig.checkGate(gateName)).to(beTrue())
            }

            it("works correctly with a valid JSON response") {
                _ = TestUtils.startWithResponseAndWait(StatsigSpec.mockUserValues)

                let gate1 = Statsig.checkGate(gateName1)
                let gate2 = Statsig.checkGate(gateName2)
                let featureGate1 = Statsig.getFeatureGateWithExposureLoggingDisabled(gateName1)
                let nonExistentGate = Statsig.checkGate(nonExistentGateName)

                let dc = Statsig.getConfig(configName)
                let exp = Statsig.getExperiment(configName)
                let nonExistentDC = Statsig.getConfig(nonExistentConfigName)

                expect(gate1).to(beFalse())
                expect(gate2).to(beTrue())
                expect(featureGate1.value).to(beFalse())
                expect(featureGate1.name).to(equal("gate_name_1"))
                expect(featureGate1.ruleID).to(equal("rule_id_1"))
                expect(featureGate1.evaluationDetails.reason).to(equal(EvaluationReason.Recognized))
                expect(featureGate1.evaluationDetails.source).to(equal(EvaluationSource.Network))
                expect(nonExistentGate).to(beFalse())

                let expectedConfig = NSDictionary(
                    dictionary: DynamicConfigSpec.TestMixedConfig["value"] as! [String: Any])
                expect(NSDictionary(dictionary: dc.value)).to(equal(expectedConfig))
                expect(NSDictionary(dictionary: exp.value)).to(equal(expectedConfig))
                expect(NSDictionary(dictionary: nonExistentDC.value)).to(equal(NSDictionary()))

                expect(dc.evaluationDetails.reason).to(equal(.Recognized))
                expect(exp.evaluationDetails.reason).to(equal(.Recognized))
                expect(nonExistentDC.evaluationDetails.reason).to(equal(.Unrecognized))

                // Now add overrides on top and check if they work
                Statsig.overrideGate(gateName1, value: true)
                expect(Statsig.checkGate(gateName1)).to(beTrue())

                Statsig.overrideGate(gateName1, value: false)
                expect(Statsig.checkGate(gateName1)).to(beFalse())

                Statsig.overrideGate("gate_fake", value: true)
                expect(Statsig.checkGate("gate_fake")).to(beTrue())

                Statsig.overrideConfig(configName, value: ["param": "value"])
                expect(
                    Statsig.getConfig(configName).getValue(forKey: "param", defaultValue: "wrong")
                ).to(equal("value"))
                expect(
                    Statsig.getExperiment(configName).getValue(
                        forKey: "param", defaultValue: "wrong")
                ).to(equal("value"))
                expect(Statsig.getConfig(configName).evaluationDetails.reason).to(
                    equal(.LocalOverride))
                expect(Statsig.getExperiment(configName).evaluationDetails.reason).to(
                    equal(.LocalOverride))

                var overrides = Statsig.getAllOverrides()
                expect(overrides?.gates.keys.count).to(equal(2))
                expect(overrides?.gates[gateName1]).to(beFalse())
                expect(overrides?.gates["gate_fake"]).to(beTrue())

                expect(overrides?.configs.keys.count).to(equal(1))
                expect(NSDictionary(dictionary: overrides!.configs[configName]!)).to(
                    equal(NSDictionary(dictionary: ["param": "value"])))

                Statsig.removeOverride(gateName1)
                expect(Statsig.checkGate(gateName1)).to(beFalse())

                Statsig.removeOverride(configName)
                expect(NSDictionary(dictionary: Statsig.getConfig(configName).value)).to(
                    equal(
                        NSDictionary(
                            dictionary: DynamicConfigSpec.TestMixedConfig["value"] as! [String: Any]
                        )))
                expect(Statsig.getConfig(configName).evaluationDetails.reason).to(
                    equal(.Recognized))

                overrides = Statsig.getAllOverrides()
                expect(overrides?.gates.keys.count).to(equal(1))
                expect(overrides?.configs.keys.count).to(equal(0))

                Statsig.removeAllOverrides()
                overrides = Statsig.getAllOverrides()
                expect(overrides?.gates.keys.count).to(equal(0))
                expect(overrides?.configs.keys.count).to(equal(0))
            }

            it("works correctly with sticky bucketing") {
                // 1. Saves sticky value and returns latest

                var response = [
                    "dynamic_configs": [
                        "exp".sha256(): [
                            "value": ["key": "exp_v1"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ]
                    ],
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["key": "layer_v1"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                            "allocated_experiment_name": "exp".sha256(),
                        ]
                    ],
                    "has_updates": true,
                ]

                _ = TestUtils.startWithResponseAndWait(response)

                var exp = Statsig.getExperiment("exp", keepDeviceValue: true)
                expect(exp.getValue(forKey: "key", defaultValue: "")).to(equal("exp_v1"))
                expect(exp.evaluationDetails.reason).to(equal(.Recognized))

                var layer = Statsig.getLayer("layer", keepDeviceValue: true)
                expect(layer.getValue(forKey: "key", defaultValue: "")).to(equal("layer_v1"))
                expect(layer.evaluationDetails.reason).to(equal(.Recognized))

                Statsig.shutdown()

                // 2. Drops user from experiment, returns the original sticky value

                response = [
                    "dynamic_configs": [
                        "exp".sha256(): [
                            "value": ["key": "exp_v2"],
                            "is_user_in_experiment": false,
                            "is_experiment_active": true,
                        ]
                    ],
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["key": "layer_v2"],
                            "is_user_in_experiment": false,
                            "is_experiment_active": true,
                            "allocated_experiment_name": "exp".sha256(),
                        ]
                    ],
                    "has_updates": true,
                ]

                _ = TestUtils.startWithResponseAndWait(response)

                exp = Statsig.getExperiment("exp", keepDeviceValue: true)
                expect(exp.getValue(forKey: "key", defaultValue: "")).to(equal("exp_v1"))
                expect(exp.evaluationDetails.reason).to(equal(.Sticky))

                layer = Statsig.getLayer("layer", keepDeviceValue: true)
                expect(layer.getValue(forKey: "key", defaultValue: "")).to(equal("layer_v1"))
                expect(layer.evaluationDetails.reason).to(equal(.Sticky))

                Statsig.shutdown()

                // 3. Deactivates experiment, returns the latest value

                response = [
                    "dynamic_configs": [
                        "exp".sha256(): [
                            "value": ["key": "exp_v3"],
                            "is_user_in_experiment": false,
                            "is_experiment_active": false,
                        ],
                        "new_exp".sha256(): [
                            "value": ["key": "new_exp_v3"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ],
                    ],
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["key": "layer_v3"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                            "allocated_experiment_name": "new_exp".sha256(),
                        ]
                    ],
                    "has_updates": true,
                ]

                _ = TestUtils.startWithResponseAndWait(response)

                exp = Statsig.getExperiment("exp", keepDeviceValue: true)
                expect(exp.getValue(forKey: "key", defaultValue: "")).to(equal("exp_v3"))
                expect(exp.evaluationDetails.reason).to(equal(.Recognized))

                layer = Statsig.getLayer("layer", keepDeviceValue: true)
                expect(layer.getValue(forKey: "key", defaultValue: "")).to(equal("layer_v3"))
                expect(layer.evaluationDetails.reason).to(equal(.Recognized))

                Statsig.shutdown()

                // 4. Drops user from the experiments, returns second sticky value

                response = [
                    "dynamic_configs": [
                        "exp".sha256(): [
                            "value": ["key": "exp_v4"],
                            "is_user_in_experiment": false,
                            "is_experiment_active": true,
                        ],
                        "new_exp".sha256(): [
                            "value": ["key": "new_exp_v4"],
                            "is_user_in_experiment": false,
                            "is_experiment_active": true,
                        ],
                    ],
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["key": "layer_v4"],
                            "is_user_in_experiment": false,
                            "is_experiment_active": true,
                            "allocated_experiment_name": "new_exp".sha256(),
                        ]
                    ],
                    "has_updates": true,
                ]

                _ = TestUtils.startWithResponseAndWait(response)

                exp = Statsig.getExperiment("exp", keepDeviceValue: true)
                expect(exp.getValue(forKey: "key", defaultValue: "")).to(equal("exp_v4"))
                expect(exp.evaluationDetails.reason).to(equal(.Recognized))

                layer = Statsig.getLayer("layer", keepDeviceValue: true)
                expect(layer.getValue(forKey: "key", defaultValue: "")).to(equal("layer_v3"))
                expect(layer.evaluationDetails.reason).to(equal(.Sticky))

                Statsig.shutdown()

                // 5. Drops all stickyness when user doesn't request it

                response = [
                    "dynamic_configs": [
                        "exp".sha256(): [
                            "value": ["key": "exp_v5"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": false,
                        ]
                    ],
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["key": "layer_v5"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": false,
                            "allocated_experiment_name": "exp".sha256(),
                        ]
                    ],
                    "has_updates": true,
                ]

                _ = TestUtils.startWithResponseAndWait(response)

                exp = Statsig.getExperiment("exp", keepDeviceValue: false)
                expect(exp.getValue(forKey: "key", defaultValue: "")).to(equal("exp_v5"))
                expect(exp.evaluationDetails.reason).to(equal(.Recognized))

                layer = Statsig.getLayer("layer", keepDeviceValue: false)
                expect(layer.getValue(forKey: "key", defaultValue: "")).to(equal("layer_v5"))
                expect(layer.evaluationDetails.reason).to(equal(.Recognized))

                // 6. Only sets sticky values when experiment is active

                exp = Statsig.getExperiment("exp", keepDeviceValue: true)
                layer = Statsig.getLayer("layer", keepDeviceValue: true)
                Statsig.shutdown()

                response = [
                    "dynamic_configs": [
                        "exp".sha256(): [
                            "value": ["key": "exp_v6"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                        ]
                    ],
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["key": "layer_v6"],
                            "is_user_in_experiment": true,
                            "is_experiment_active": true,
                            "allocated_experiment_name": "exp".sha256(),
                        ]
                    ],
                    "has_updates": true,
                ]

                _ = TestUtils.startWithResponseAndWait(response)

                exp = Statsig.getExperiment("exp", keepDeviceValue: true)
                expect(exp.getValue(forKey: "key", defaultValue: "")).to(equal("exp_v6"))
                expect(exp.evaluationDetails.reason).to(equal(.Recognized))

                layer = Statsig.getLayer("layer", keepDeviceValue: true)
                expect(layer.getValue(forKey: "key", defaultValue: "")).to(equal("layer_v6"))
                expect(layer.evaluationDetails.reason).to(equal(.Recognized))

                Statsig.shutdown()
            }

            it(
                "times out if the request took too long and responds early with default values, when there is no local cache"
            ) {
                stub(condition: isHost(ApiHost)) { _ in
                    HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil
                    )
                    .responseTime(0.2)
                }

                var errorCode: StatsigClientErrorCode?
                var gate: Bool?
                var dc: DynamicConfig?
                let timeBefore = CFAbsoluteTimeGetCurrent()
                var timeDiff = 0.0

                let initTimeoutExpect = self.expectation(description: "Init Timeout")
                Statsig.initialize(
                    sdkKey: "client-api-key",
                    options: StatsigOptions(initTimeout: 0.1, disableDiagnostics: true)
                ) { err in
                    errorCode = err?.code
                    gate = Statsig.checkGate(gateName2)
                    dc = Statsig.getConfig(configName)
                    timeDiff = CFAbsoluteTimeGetCurrent() - timeBefore
                    initTimeoutExpect.fulfill()
                }

                self.wait(for: [initTimeoutExpect], timeout: 0.15)

                // check the values immediately following the completion block from start() assignments
                expect(errorCode).to(equal(StatsigClientErrorCode.initTimeoutExpired))
                expect(gate).to(beFalse())
                expect(NSDictionary(dictionary: dc!.value)).to(equal(NSDictionary(dictionary: [:])))
                expect(dc!.evaluationDetails.reason).to(equal(.Unrecognized))
                expect(timeDiff).to(beCloseTo(0.1, within: 0.05))

                waitUntil { done in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        done()
                    }
                }

                // check the same gate and config >0.01 seconds later should return the original results
                expect(errorCode).to(equal(StatsigClientErrorCode.initTimeoutExpired))
                expect(gate).to(beFalse())
                expect(NSDictionary(dictionary: dc!.value)).to(equal(NSDictionary(dictionary: [:])))
                expect(dc!.evaluationDetails.reason).to(equal(.Unrecognized))
                expect(timeDiff).to(beCloseTo(0.1, within: 0.05))
            }

            it("times out and returns value from local cache") {
                stub(condition: isHost(ApiHost)) { _ in
                    HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                }

                var gate: Bool?
                var nonExistentGate: Bool?
                var dc: DynamicConfig?
                var exp: DynamicConfig?
                var nonExistentDC: DynamicConfig?

                // First call initialize() to fetch and store values in local storage
                Statsig.initialize(
                    sdkKey: "client-api-key", options: StatsigOptions(disableDiagnostics: true)
                ) { _ in
                    // shutdown client to call initialize() again, and makes response slow so we can test early timeout with cached return
                    Statsig.shutdown()
                    stub(condition: isHost(ApiHost)) { _ in
                        HTTPStubsResponse(
                            jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil
                        ).responseTime(3)
                    }

                    Statsig.initialize(
                        sdkKey: "client-api-key",
                        options: StatsigOptions(initTimeout: 0.1, disableDiagnostics: true)
                    ) { _ in
                        gate = Statsig.checkGate(gateName2)
                        nonExistentGate = Statsig.checkGate(nonExistentGateName)
                        dc = Statsig.getConfig(configName)
                        exp = Statsig.getExperiment(configName)
                        nonExistentDC = Statsig.getConfig(nonExistentConfigName)
                    }
                }

                expect(gate).toEventually(beTrue())
                expect(nonExistentGate).toEventually(beFalse())
                expect(dc).toEventuallyNot(beNil())
                expect(dc?.evaluationDetails.reason).toEventually(equal(.Recognized))
                expect(exp).toEventuallyNot(beNil())
                expect(exp?.evaluationDetails.reason).toEventually(equal(.Recognized))
                expect(NSDictionary(dictionary: nonExistentDC!.value)).toEventually(
                    equal(NSDictionary(dictionary: [:])))
                expect(nonExistentDC?.evaluationDetails.reason).toEventually(equal(.Unrecognized))
            }

            it("correctly shuts down") {
                stub(condition: isPath("/v1/initialize")) { _ in
                    HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                }

                var events: [[String: Any]] = []
                var statsigMetadata: [String: String?] = [:]
                stub(condition: isPath("/v1/rgstr")) { request in
                    let actualRequestHttpBody =
                        try! JSONSerialization.jsonObject(
                            with: request.ohhttpStubs_httpBody!,
                            options: []) as! [String: Any]
                    events = (actualRequestHttpBody["events"] as! [[String: Any]]).filter({ item in
                        return item["eventName"] as? String != "statsig::diagnostics"
                    })
                    statsigMetadata = actualRequestHttpBody["statsigMetadata"] as! [String: String?]
                    return HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                }

                var gate: Bool?
                var config: DynamicConfig?
                var exp: DynamicConfig?
                var stableID: String?
                waitUntil { done in
                    Statsig.initialize(
                        sdkKey: "client-api-key",
                        user: StatsigUser(userID: "123", email: "123@statsig.com"),
                        options: StatsigOptions(
                            overrideStableID: "custom_stable_id", disableDiagnostics: true)
                    ) { err in
                        expect(err).to(beNil())

                        // Event 0
                        gate = Statsig.checkGate(gateName2)
                        _ = Statsig.checkGate(gateName2)  // should not create an exposure, deduped

                        // Event 1
                        exp = Statsig.getExperiment(configName)
                        config = Statsig.getConfig(configName)  // should not create an exposure, deduped
                        stableID = Statsig.getStableID()

                        // Event 2
                        Statsig.logEvent("test_event", value: 1, metadata: ["key": "value1"])

                        // Event 3
                        Statsig.logEvent("test_event_2", value: "1", metadata: ["key": "value2"])

                        // Event 4
                        Statsig.logEvent("test_event_3", metadata: ["key": "value3"])

                        Statsig.updateUserWithResult(
                            StatsigUser(userID: "123", email: "123@statsig.com")
                        ) { error in
                            // Event 5
                            _ = Statsig.checkGate(gateName2)  // should create an exposure, no longer dedupe after updating user
                            Statsig.shutdown()
                            done()
                        }
                    }
                }

                expect(gate).to(beTrue())
                expect(NSDictionary(dictionary: config!.value)).to(
                    equal(
                        NSDictionary(
                            dictionary: DynamicConfigSpec.TestMixedConfig["value"] as! [String: Any]
                        )
                    )
                )
                expect(NSDictionary(dictionary: exp!.value)).to(
                    equal(
                        NSDictionary(
                            dictionary: DynamicConfigSpec.TestMixedConfig["value"] as! [String: Any]
                        )
                    )
                )

                expect(events.count).toEventually(equal(6))

                var event = events[0]
                var user = event["user"] as! [String: Any]
                var metadata = event["metadata"] as! [String: Any]?
                var secondaryExposures = event["secondaryExposures"] as! [[String: String]]?
                var value = event["value"]

                expect(event["eventName"] as? String).to(
                    equal(Event.statsigPrefix + Event.gateExposureEventName))
                expect(user["userID"] as? String).to(equal("123"))
                expect(user["email"] as? String).to(equal("123@statsig.com"))
                expect(NSDictionary(dictionary: metadata!)).to(
                    equal(
                        NSDictionary(dictionary: [
                            "gate": "gate_name_2",
                            "gateValue": "true",
                            "ruleID": "rule_id_2",
                            "reason": "Network:Recognized",
                            "lcut": "0",
                            "receivedAt": metadata!["receivedAt"]!,
                        ]))
                )
                expect(secondaryExposures).to(equal([]))
                expect(value).to(beNil())

                event = events[1]
                user = event["user"] as! [String: Any]
                metadata = event["metadata"] as! [String: Any]?
                secondaryExposures = event["secondaryExposures"] as! [[String: String]]?
                value = event["value"]

                expect(event["eventName"] as? String).to(
                    equal(Event.statsigPrefix + Event.configExposureEventName))
                expect(user["userID"] as? String).to(equal("123"))
                expect(user["email"] as? String).to(equal("123@statsig.com"))
                expect(NSDictionary(dictionary: metadata!)).to(
                    equal(
                        NSDictionary(dictionary: [
                            "config": "config",
                            "ruleID": "default",
                            "reason": "Network:Recognized",
                            "lcut": "0",
                            "receivedAt": metadata!["receivedAt"]!,
                            "rulePassed": "false",
                        ]))
                )
                expect(secondaryExposures).to(equal([]))
                expect(value).to(beNil())

                event = events[2]
                user = event["user"] as! [String: Any]
                metadata = event["metadata"] as! [String: Any]?
                secondaryExposures = event["secondaryExposures"] as! [[String: String]]?
                value = event["value"]

                expect(event["eventName"] as? String).to(equal("test_event"))
                expect(user["userID"] as? String).to(equal("123"))
                expect(user["email"] as? String).to(equal("123@statsig.com"))
                expect(NSDictionary(dictionary: metadata!)).to(
                    equal(NSDictionary(dictionary: ["key": "value1"])))
                expect(secondaryExposures).to(beNil())
                expect(value as? Int).to(equal(1))

                event = events[3]
                user = event["user"] as! [String: Any]
                metadata = event["metadata"] as! [String: Any]?
                secondaryExposures = event["secondaryExposures"] as! [[String: String]]?
                value = event["value"]

                expect(event["eventName"] as? String).to(equal("test_event_2"))
                expect(user["userID"] as? String).to(equal("123"))
                expect(user["email"] as? String).to(equal("123@statsig.com"))
                expect(NSDictionary(dictionary: metadata!)).to(
                    equal(NSDictionary(dictionary: ["key": "value2"])))
                expect(secondaryExposures).to(beNil())
                expect(value as? String).to(equal("1"))

                event = events[4]
                user = event["user"] as! [String: Any]
                metadata = event["metadata"] as! [String: Any]?
                secondaryExposures = event["secondaryExposures"] as! [[String: String]]?
                value = event["value"]

                expect(event["eventName"] as? String).to(equal("test_event_3"))
                expect(user["userID"] as? String).to(equal("123"))
                expect(user["email"] as? String).to(equal("123@statsig.com"))
                expect(NSDictionary(dictionary: metadata!)).to(
                    equal(NSDictionary(dictionary: ["key": "value3"])))
                expect(secondaryExposures).to(beNil())
                expect(value).to(beNil())

                event = events[5]
                user = event["user"] as! [String: Any]
                metadata = event["metadata"] as! [String: Any]?
                secondaryExposures = event["secondaryExposures"] as! [[String: String]]?
                value = event["value"]

                expect(event["eventName"] as? String).to(
                    equal(Event.statsigPrefix + Event.gateExposureEventName))
                expect(user["userID"] as? String).to(equal("123"))
                expect(user["email"] as? String).to(equal("123@statsig.com"))
                expect(NSDictionary(dictionary: metadata!)).to(
                    equal(
                        NSDictionary(dictionary: [
                            "gate": "gate_name_2",
                            "gateValue": "true",
                            "ruleID": "rule_id_2",
                            "reason": "Network:Recognized",
                            "lcut": "0",
                            "receivedAt": metadata!["receivedAt"]!,
                        ]))
                )
                expect(secondaryExposures).to(equal([]))
                expect(value).to(beNil())

                // validate stable ID
                expect(statsigMetadata[StatsigMetadata.STABLE_ID_KEY]).to(equal("custom_stable_id"))
                expect(stableID).to(equal("custom_stable_id"))
            }

            it("correctly initializes when using the deprecated Statsig.start") {
                var initialized = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)
                Statsig.start(sdkKey: "client-api-key", options: opts) { _ in
                    initialized = Statsig.isInitialized()
                }

                expect(initialized).toEventually(beTrue())
            }

            it("fully populates StatsigMetadata") {
                _ =
                    TestUtils
                    .startWithResponseAndWait(
                        StatsigSpec.mockUserValues,
                        "client-api-key",
                        StatsigUser(userID: "whd")
                    )

                let statsigMetadata = Statsig.getStatsigMetadata() ?? StatsigMetadata()
                expect(statsigMetadata).notTo(beNil())
                expect(statsigMetadata.stableID).notTo(beNil())
                expect(statsigMetadata.sdkType).notTo(beNil())
                expect(statsigMetadata.sdkVersion).notTo(beNil())
                expect(statsigMetadata.sessionID).notTo(beNil())
                expect(statsigMetadata.appIdentifier).notTo(beNil())
                expect(statsigMetadata.appVersion).notTo(beNil())
                expect(statsigMetadata.deviceModel).notTo(beNil())
                expect(statsigMetadata.deviceOS).notTo(beNil())
                expect(statsigMetadata.locale).notTo(beNil())
                expect(statsigMetadata.language).notTo(beNil())
                expect(statsigMetadata.systemVersion).notTo(beNil())
                expect(statsigMetadata.systemName).notTo(beNil())
            }

            it("does not fully populate StatsigMetadata for optOut user") {
                _ =
                    TestUtils
                    .startWithResponseAndWait(
                        StatsigSpec.mockUserValues,
                        "client-api-key",
                        StatsigUser(optOutNonSdkMetadata: true)
                    )
                let statsigMetadata = Statsig.getStatsigMetadata() ?? StatsigMetadata()
                expect(statsigMetadata).notTo(beNil())

                // Expect these fields
                expect(statsigMetadata.stableID).notTo(beNil())
                expect(statsigMetadata.sdkType).notTo(beNil())
                expect(statsigMetadata.sdkVersion).notTo(beNil())
                expect(statsigMetadata.sessionID).notTo(beNil())

                // These fields should be nil
                expect(statsigMetadata.appIdentifier).to(beNil())
                expect(statsigMetadata.appVersion).to(beNil())
                expect(statsigMetadata.deviceModel).to(beNil())
                expect(statsigMetadata.deviceOS).to(beNil())
                expect(statsigMetadata.locale).to(beNil())
                expect(statsigMetadata.language).to(beNil())
                expect(statsigMetadata.systemVersion).to(beNil())
                expect(statsigMetadata.systemName).to(beNil())
            }
        }
    }
}
