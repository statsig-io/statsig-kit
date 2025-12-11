import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

extension Dictionary {
    subscript(d key: Key) -> [String: Any]? {
        get {
            return self[key] as? [String: Any]
        }
    }

    subscript(a key: Key) -> [Any]? {
        get {
            return self[key] as? [Any]
        }
    }
}

extension Array {
    subscript(d key: Index) -> [String: Any]? {
        get {
            return self[key] as? [String: Any]
        }
    }

    subscript(a key: Index) -> [Any]? {
        get {
            return self[key] as? [Any]
        }
    }
}

class LayerExposureSpec: BaseSpec {

    private static let lcut = 123456

    override func spec() {
        super.spec()

        describe("Layer Exposure Logging") {
            it("logs layers without an allocated experiment correctly") {
                _ = TestUtils.startWithResponseAndWait([
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["an_int": 99],
                            "rule_id": "default",
                            "secondary_exposures": [["gate": "secondary_exp"]],
                            "undelegated_secondary_exposures": [
                                ["gate": "undelegated_secondary_exp"]
                            ],
                            "allocated_experiment_name": "",
                            "explicit_parameters": [],
                        ]
                    ],
                    "time": LayerExposureSpec.lcut,
                    "has_updates": true,
                ])

                let layer = Statsig.getLayer("layer")
                _ = layer.getValue(forKey: "an_int", defaultValue: 0)

                var logs: [String: Any]!
                TestUtils.captureLogs { captured in
                    logs = captured
                }
                Statsig.shutdown()

                expect(logs).toEventuallyNot(beNil())

                expect(logs[a: "events"]?.count).toEventually(equal(1))
                let event = logs[a: "events"]?[d: 0]
                expect(event?[a: "secondaryExposures"] as? [[String: String]])
                    .to(equal([["gate": "undelegated_secondary_exp"]]))
                let metadata = event?[d: "metadata"] as! [String: String]
                expect(metadata)
                    .to(
                        equal([
                            "config": "layer",
                            "ruleID": "default",
                            "allocatedExperiment": "",
                            "parameterName": "an_int",
                            "isExplicitParameter": "false",
                            "reason": "Network:Recognized",
                            "lcut": "\(LayerExposureSpec.lcut)",
                            "receivedAt": metadata["receivedAt"]!,
                        ]))
            }

            it("logs explicit and implicit parameters correctly") {
                _ = TestUtils.startWithResponseAndWait([
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": ["an_int": 99, "a_string": "value"],
                            "rule_id": "default",
                            "secondary_exposures": [["gate": "secondary_exp"]],
                            "undelegated_secondary_exposures": [
                                ["gate": "undelegated_secondary_exp"]
                            ],
                            "allocated_experiment_name": "the_allocated_experiment",
                            "explicit_parameters": ["an_int"],
                        ]
                    ],
                    "time": LayerExposureSpec.lcut,
                    "has_updates": true,
                ])

                let layer = Statsig.getLayer("layer")
                _ = layer.getValue(forKey: "an_int", defaultValue: 0)
                _ = layer.getValue(forKey: "a_string", defaultValue: "")

                var logs: [String: Any]!
                TestUtils.captureLogs { captured in
                    logs = captured
                }
                Statsig.shutdown()

                expect(logs).toEventuallyNot(beNil())

                let events = logs[a: "events"]
                expect(events?.count).to(equal(2))

                let explicitEvent = events?[d: 0]
                var metadata = explicitEvent?[d: "metadata"] as! [String: String]
                expect(explicitEvent?[a: "secondaryExposures"] as? [[String: String]])
                    .to(equal([["gate": "secondary_exp"]]))
                expect(metadata)
                    .to(
                        equal([
                            "config": "layer",
                            "ruleID": "default",
                            "allocatedExperiment": "the_allocated_experiment",
                            "parameterName": "an_int",
                            "isExplicitParameter": "true",
                            "reason": "Network:Recognized",
                            "lcut": "\(LayerExposureSpec.lcut)",
                            "receivedAt": metadata["receivedAt"]!,
                        ]))

                let implicitEvent = events?[d: 1]
                metadata = implicitEvent?[d: "metadata"] as! [String: String]
                expect(implicitEvent?[a: "secondaryExposures"] as? [[String: String]])
                    .to(equal([["gate": "undelegated_secondary_exp"]]))
                expect(metadata)
                    .to(
                        equal([
                            "config": "layer",
                            "ruleID": "default",
                            "allocatedExperiment": "",
                            "parameterName": "a_string",
                            "isExplicitParameter": "false",
                            "reason": "Network:Recognized",
                            "lcut": "\(LayerExposureSpec.lcut)",
                            "receivedAt": metadata["receivedAt"]!,
                        ]))
            }

            it("logs different object types correctly") {
                _ = TestUtils.startWithResponseAndWait([
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": [
                                "a_bool": true,
                                "an_int": 99,
                                "a_double": 1.23,
                                "a_long": UInt64(1),
                                "a_string": "value",
                                "an_array": ["a", "b"],
                                "an_object": ["key": "value"],
                            ]
                        ]
                    ],
                    "has_updates": true,
                ])

                let layer = Statsig.getLayer("layer")
                _ = layer.getValue(forKey: "a_bool", defaultValue: false)
                _ = layer.getValue(forKey: "an_int", defaultValue: 0)
                _ = layer.getValue(forKey: "a_double", defaultValue: 0.0)
                _ = layer.getValue(forKey: "a_long", defaultValue: 0)
                _ = layer.getValue(forKey: "a_string", defaultValue: "")
                _ = layer.getValue(forKey: "an_array", defaultValue: [])
                _ = layer.getValue(forKey: "an_object", defaultValue: [:])

                var logs: [String: Any]!
                TestUtils.captureLogs { captured in
                    logs = captured
                }
                Statsig.shutdown()

                expect(logs).toEventuallyNot(beNil())

                let events = logs[a: "events"]
                expect(events?.count).to(equal(7))
            }

            it("does not log when shutdown") {
                _ = TestUtils.startWithResponseAndWait([
                    "layer_configs": [
                        "layer".sha256(): [
                            "value": [
                                "a_bool": true
                            ]
                        ]
                    ],
                    "has_updates": true,
                ])

                let layer = Statsig.getLayer("layer")
                var logs: [String: Any]!
                TestUtils.captureLogs { captured in
                    logs = captured
                }
                Statsig.shutdown()

                _ = layer.getValue(forKey: "a_bool", defaultValue: false)

                expect(logs).to(beNil())
            }

            it("logs the correct name and user values") {
                _ = TestUtils.startWithResponseAndWait(
                    [
                        "layer_configs": [
                            "layer".sha256(): [
                                "value": ["an_int": 99]
                            ]
                        ],
                        "has_updates": true,
                    ], "client-sdk-key", StatsigUser(userID: "dloomb", email: "dan@loomb.co.nz"))

                let layer = Statsig.getLayer("layer")
                _ = layer.getValue(forKey: "an_int", defaultValue: 0)

                var logs: [String: Any]!
                TestUtils.captureLogs { captured in
                    logs = captured
                }
                Statsig.shutdown()

                expect(logs).toEventuallyNot(beNil())

                expect(logs[a: "events"]?.count).toEventually(equal(1))
                let event = logs[a: "events"]?[d: 0]
                expect(event?["eventName"] as? String)
                    .to(equal("statsig::layer_exposure"))

                expect(event?["user"] as? [String: AnyHashable])
                    .to(
                        equal([
                            "userID": "dloomb",
                            "email": "dan@loomb.co.nz",
                            "statsigEnvironment": [String: String](),
                        ]))
            }
        }
    }
}
