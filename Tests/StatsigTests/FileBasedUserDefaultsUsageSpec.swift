import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class FileBasedUserDefaultsUsageSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("FileBasedUserDefaultsUsage") {
            beforeEach {
                _ = TestUtils.startWithResponseAndWait(
                    [
                        "feature_gates": [],
                        "dynamic_configs": [
                            "a_config".sha256(): [
                                "value": ["a_bool": true]
                            ]
                        ],
                        "layer_configs": [],
                        "time": 321,
                        "has_updates": true,
                    ], options: StatsigOptions(enableCacheByFile: true, disableDiagnostics: true))
            }

            it("returns config from network") {
                let result = Statsig.getConfig("a_config")
                expect(result.value as? [String: Bool]).to(equal(["a_bool": true]))
                expect(result.evaluationDetails.reason).to(equal(.Recognized))
            }

            it("returns config from cache") {
                Statsig.shutdown()

                _ = TestUtils.startWithStatusAndWait(
                    500, options: StatsigOptions(enableCacheByFile: true, disableDiagnostics: true))

                let result = Statsig.getConfig("a_config")
                expect(result.value as? [String: Bool]).to(equal(["a_bool": true]))
                expect(result.evaluationDetails.reason).to(equal(EvaluationReason.Recognized))
            }
        }
    }
}
