import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class MultiClientSupportSpec: BaseSpec {
    override func spec() {
        super.spec()

        let baseResponse: [String: Any] = [
            "feature_gates": [
                "a_gate": [
                    "value": true
                ]
            ],
            "dynamic_configs": [],
            "hash_used": "none",
            "layer_configs": [],
            "time": 123,
            "has_updates": true,
        ]

        func stubInitOnce(_ response: [String: Any]) {
            var handle: HTTPStubsDescriptor?

            handle = stub(condition: isHost(ApiHost)) { req in
                HTTPStubs.removeStub(handle!)
                return HTTPStubsResponse(jsonObject: response, statusCode: 200, headers: nil)
            }
        }

        describe("MultiClientSupport") {
            var clientA: StatsigClient?
            var clientB: StatsigClient?
            var defaults: MockDefaults?
            var requests: [URLRequest] = []

            beforeEach {
                // Setup Mock Caching
                defaults = MockDefaults()
                StatsigUserDefaults.defaults = defaults!

                // Setup Event Capture
                requests = []
                stub(condition: isPath("/v1/rgstr")) { request in
                    requests.append(request)
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                // Initialize Client Instance A
                stubInitOnce(baseResponse)
                waitUntil { done in
                    clientA = StatsigClient(sdkKey: "client-key-a", completion: { err in done() })
                }

                // Initialize Client Instance B
                var updatedResponse = baseResponse
                updatedResponse["feature_gates"] = [
                    "b_gate": [
                        "value": true
                    ]
                ]
                stubInitOnce(updatedResponse)
                waitUntil { done in
                    clientB = StatsigClient(sdkKey: "client-key-b", completion: { err in done() })
                }
            }

            it("gets different gate results") {
                expect(clientA?.checkGate("a_gate")).to(beTrue())
                expect(clientA?.checkGate("b_gate")).to(beFalse())

                expect(clientB?.checkGate("a_gate")).to(beFalse())
                expect(clientB?.checkGate("b_gate")).to(beTrue())
            }

            it("saves both users values to storage") {
                let values = defaults?.getUserCaches()
                expect(values?.allKeys).to(haveCount(2))
            }

            it("logs separate exposure events") {
                _ = clientA?.checkGate("a_gate")
                _ = clientB?.checkGate("a_gate")

                clientA?.flush()
                clientB?.flush()

                expect(requests).toEventually(haveCount(2))
            }
        }
    }
}
