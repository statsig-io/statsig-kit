import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class AutoUpdateSpec: BaseSpec {
    override func spec() {
        super.spec()

        let opts = StatsigOptions(
            enableAutoValueUpdate: true,
            autoValueUpdateIntervalSec: 0.001,
            api: "http://AutoUpdateSpec"
        )

        it("syncs when started from the background thread") {
            Statsig.shutdown()

            var callsMade = 0
            stub(condition: isHost("AutoUpdateSpec")) { req in
                if req.url?.absoluteString.contains("/initialize") ?? false {
                    callsMade += 1
                }
                return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
            }

            DispatchQueue.global().sync {
                TestUtils.startStatsigAndWait(key: "client-key", nil, opts)
            }

            expect(callsMade).toEventually(beGreaterThanOrEqualTo(10))
        }

        it("pulls in changed values") {
            Statsig.shutdown()

            var response = [
                "feature_gates": [:],
                "dynamic_configs": [:],
                "layer_configs": [:],
                "has_updates": true,
            ]

            stub(condition: isHost("AutoUpdateSpec")) { req in
                return HTTPStubsResponse(jsonObject: response, statusCode: 200, headers: nil)
            }

            TestUtils.startStatsigAndWait(key: "client-key", nil, opts)

            expect(Statsig.checkGate("a_gate")).to(beFalse())

            response = [
                "feature_gates": [
                    "a_gate".sha256(): [
                        "value": true,
                        "rule_id": "rule_id_1",
                        "secondary_exposures": [],
                    ]
                ],
                "dynamic_configs": [:],
                "layer_configs": [:],
                "has_updates": true,
            ]

            expect(Statsig.checkGate("a_gate")).toEventually(beTrue())
        }
    }
}
