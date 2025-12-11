import Foundation
import Nimble
import OHHTTPStubs
import Quick
import SwiftUI

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class NullInitializeSpec: BaseSpec {
    static let mockUserValues: [String: Any] = [
        "feature_gates": [],
        "dynamic_configs": [
            "config".sha256(): DynamicConfigSpec.TestMixedConfig,
            "null_value_config".sha256(): [
                "rule_id": "default",
                "value":
                    [
                        "str": "string",
                        "null": nil,
                    ],
            ],
        ],
        "layer_configs": [],
        "has_updates": true,
    ]

    override func spec() {
        super.spec()

        describe("Nil and Statsig") {
            beforeEach {
                TestUtils.clearStorage()

                stub(condition: isHost(ApiHost)) { _ in
                    HTTPStubsResponse(
                        jsonObject: StatsigSpec.mockUserValues, statusCode: 200, headers: nil)
                }
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
                TestUtils.clearStorage()
            }

            it("works when initialize contains null") {
                var called = false
                waitUntil { done in
                    let opts = StatsigOptions(disableDiagnostics: true)
                    Statsig.initialize(sdkKey: "client-api-key", options: opts) { _ in
                        let config = Statsig.getConfig("null_value_config")

                        let defaultVal = config.getValue(forKey: "null", defaultValue: "default")
                        expect(defaultVal).to(equal("default"))
                        called = true
                        done()
                    }
                }

                expect(called).to(beTrue())
            }

            it("works when override contains null") {
                var called = false
                waitUntil { done in
                    let opts = StatsigOptions(disableDiagnostics: true)
                    Statsig.initialize(sdkKey: "client-api-key", options: opts) { _ in

                        let dict = ["foo": nil] as [String: Any?]
                        Statsig.overrideConfig("config", value: dict as [String: Any])

                        Statsig.initialize(sdkKey: "client-api-key") { _ in
                            let config = Statsig.getConfig("config")

                            let defaultVal = config.getValue(forKey: "foo", defaultValue: "default")
                            expect(defaultVal).to(equal("default"))
                            called = true
                            done()
                        }
                    }
                }
                expect(called).to(beTrue())
            }
        }

    }
}
