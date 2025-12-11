import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class ManyThreadsSpec: BaseSpec {
    static let Response: [String: Any] = [
        "feature_gates": [
            "a_gate".sha256(): [
                "value": true
            ]
        ],
        "dynamic_configs": [],
        "layer_configs": [],
        "time": 123,
        "has_updates": true,
    ]

    override func spec() {
        super.spec()

        func executeManyTimes(_ action: @escaping () -> Void) {
            let totalThreads = 5
            var activeThreads = totalThreads

            let decrementActiveThreads = {
                activeThreads -= 1
            }

            for _ in 1...totalThreads {
                DispatchQueue.global(qos: .userInitiated).async {
                    for _ in 1...1000 {
                        action()
                    }
                    DispatchQueue.main.async {
                        decrementActiveThreads()
                    }
                }
            }

            expect(activeThreads).toEventually(equal(0), timeout: .seconds(2))
        }

        describe("Many Threads") {
            beforeEach {
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                _ = TestUtils.startWithResponseAndWait(ManyThreadsSpec.Response)
            }

            afterEach {
                Statsig.shutdown()
            }

            it("is safe to call check gate without exposures") {
                executeManyTimes {
                    _ = Statsig.checkGateWithExposureLoggingDisabled("a_gate")
                }
            }

            it("is safe to call check gate with exposures") {
                executeManyTimes {
                    _ = Statsig.checkGate("a_gate")
                }
            }

            it("is safe to call log event") {
                executeManyTimes {
                    Statsig.logEvent("an_event")
                }
            }
        }
    }
}
