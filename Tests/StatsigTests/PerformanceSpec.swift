import Foundation

import XCTest
import Nimble
import OHHTTPStubs
import Quick
@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class PerformanceSpec: XCTestCase {

    override func setUpWithError() throws {
        let opts = StatsigOptions(disableDiagnostics: true)
        NetworkService.defaultInitializationURL = URL(string: "http://PerformanceSpec/v1/initialize")

        _ = TestUtils.startWithResponseAndWait([
            "feature_gates": [
                "a_gate".sha256(): [
                    "value": true
                ],
                "addresssuggestionabexperimentname".sha256(): [
                    "value": true
                ],
                "repro_gate".sha256(): [
                    "value": false
                ],
                "test.gate.with.periods".sha256(): [
                    "value": true
                ],
                "test_progressive_rollout".sha256(): [
                    "value": false
                ],
                "test_off_gate".sha256(): [
                    "value": false
                ],
                "a_gate_from_console".sha256(): [
                    "value": true
                ],
                "test_roullout".sha256(): [
                    "value": true
                ],
                "test-aos-application-sfaccountid".sha256(): [
                    "value": false
                ],
                "testing_country".sha256(): [
                    "value": true
                ],
                "devicetype".sha256(): [
                    "value": false
                ]
            ],
            "dynamic_configs": [
                "a_config".sha256(): [
                    "value": ["a_bool": true],
                ],
                "test_solo_experiment".sha256(): [
                    "value": ["param1": "value1"],
                ],
                "exp1".sha256(): [
                    "value": ["param2": "value2"],
                ],
                "testing_experiments".sha256(): [
                    "value": ["param3": "value3"],
                ],
                "a_new_experiment".sha256(): [
                    "value": ["param4": "value4"],
                ],
                "master_layer_a_a".sha256(): [
                    "value": ["param5": "value5"],
                ],
                "a_a_test".sha256(): [
                    "value": ["param6": "value6"],
                ],
                "half".sha256(): [
                    "value": ["param7": "value7"],
                ],
                "tenten80".sha256(): [
                    "value": ["param8": "value8"],
                ],
                "test_parameters".sha256(): [
                    "value": ["param9": "value9"],
                ],
                "exp_in_layer".sha256(): [
                    "value": ["param10": "value10"],
                ]
            ],
            "layer_configs": [
                "a_layer".sha256(): [
                    "value": ["a_bool": true],
                ]
            ],
            "time": 321,
            "has_updates": true
        ], options: opts)
    }

    override func tearDownWithError() throws {
        Statsig.client?.shutdown()
        Statsig.client = nil
        TestUtils.resetDefaultURLs()
    }

    func testCheckGatePerformance() throws {
        self.measure {
            for _ in 0...10 {
                let result = Statsig.checkGate("a_gate")
                expect(result).to(beTrue())
            }
        }
    }

    func testGetExperimentPerformance() throws {
        self.measure {
            for _ in 0...10 {
                let result = Statsig.getExperiment("a_config")
                expect(result.getValue(forKey: "a_bool", defaultValue: false)).to(beTrue())
            }
        }
    }

    func testGetLayerPerformance() throws {
        self.measure {
            for _ in 0...10 {
                let result = Statsig.getLayer("a_layer")
                expect(result.getValue(forKey: "a_bool", defaultValue: false)).to(beTrue())
            }
        }
    }

    func testBenchmarkCheckGate() throws {
        // Comment next line to run benchmark
        try XCTSkipIf(true, "Benchmark skipped by default")
        
        let iterations = 10_000
        let gateNames = [
            "addresssuggestionabexperimentname",
            "repro_gate",
            "test.gate.with.periods",
            "test_progressive_rollout",
            "test_off_gate",
            "a_gate_from_console",
            "test_roullout",
            "test-aos-application-sfaccountid",
            "testing_country",
            "devicetype"
        ]

        self.measure {
            for _ in 0..<iterations {
                for gate in gateNames {
                    _ = Statsig.checkGate(gate)
                }
            }
        }
    }

    func testBenchmarkGetExperiment() throws {
        // Comment next line to run benchmark
        try XCTSkipIf(true, "Benchmark skipped by default")
        
        let iterations = 10_000
        let experimentNames = [
            "test_solo_experiment",
            "exp1",
            "testing_experiments",
            "a_new_experiment",
            "master_layer_a_a",
            "a_a_test",
            "half",
            "tenten80",
            "test_parameters",
            "exp_in_layer"
        ]

        self.measure {
            for _ in 0..<iterations {
                for exp in experimentNames {
                    _ = Statsig.getExperiment(exp)
                }
            }
        }
    }

}
