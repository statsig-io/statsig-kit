import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class StorageProviderBasedUserDefaultsUsageSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("StorageProviderBasedUserDefaultsUsage") {
            let customStorageProvider = MockStorageProvider()
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
                    ],
                    options: StatsigOptions(
                        disableDiagnostics: true, storageProvider: customStorageProvider))
            }

            it("returns config from network") {
                let result = Statsig.getConfig("a_config")
                expect(result.value as? [String: Bool]).to(equal(["a_bool": true]))
                expect(result.evaluationDetails.reason).to(equal(.Recognized))
            }

            it("returns config from cache") {
                Statsig.shutdown()

                _ = TestUtils.startWithStatusAndWait(
                    500,
                    options: StatsigOptions(
                        disableDiagnostics: true, storageProvider: customStorageProvider))

                let result = Statsig.getConfig("a_config")
                expect(result.value as? [String: Bool]).to(equal(["a_bool": true]))
                expect(result.evaluationDetails.reason).to(equal(EvaluationReason.Recognized))
            }

            afterSuite {
                StatsigUserDefaults.defaults = UserDefaults.standard
                Statsig.shutdown()
            }

            func clearUserDefaults() {
                let defaultsDictionary = UserDefaults.standard.dictionaryRepresentation()
                for key in defaultsDictionary.keys {
                    UserDefaults.standard.removeObject(forKey: key)
                }
                UserDefaults.standard.synchronize()
            }

            afterEach {
                StatsigUserDefaults.defaults = UserDefaults.standard
                clearUserDefaults()
                Statsig.shutdown()
            }
        }
    }
}
