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
            func shutdownAndWait() {
                guard let client = Statsig.client else {
                    Statsig.client = nil
                    return
                }

                waitUntil(timeout: .seconds(10)) { done in
                    client.shutdown {
                        Statsig.client = nil
                        done()
                    }
                }
            }

            beforeEach {
                TestUtils.clearStorage()
                BaseSpec.resetUserDefaults()
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

                expect(FileBasedUserDefaults().dictionary(forKey: UserDefaultsKeys.localStorageKey))
                    .toEventuallyNot(beNil())
                expect(
                    FileBasedUserDefaults().dictionary(forKey: UserDefaultsKeys.cacheKeyMappingKey)
                )
                .toEventuallyNot(beNil())
            }

            it("returns config from network") {
                let result = Statsig.getConfig("a_config")
                expect(result.value as? [String: Bool]).to(equal(["a_bool": true]))
                expect(result.evaluationDetails.reason).to(equal(.Recognized))
            }

            it("returns config from cache") {
                shutdownAndWait()

                _ = TestUtils.startWithStatusAndWait(
                    500, options: StatsigOptions(enableCacheByFile: true, disableDiagnostics: true))

                let result = Statsig.getConfig("a_config")
                expect(result.value as? [String: Bool]).to(equal(["a_bool": true]))
                expect(result.evaluationDetails.reason).to(equal(EvaluationReason.Recognized))
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                shutdownAndWait()
                TestUtils.clearStorage()
                TestUtils.resetDefaultURLs()
                BaseSpec.resetUserDefaults()
            }
        }
    }
}
