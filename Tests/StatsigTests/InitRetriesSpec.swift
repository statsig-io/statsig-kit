import Foundation
import Nimble
import OHHTTPStubs
import Quick
import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class InitRetriesSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("Init Retries") {
            it("logs to the endpoint") {
                var calls = 0
                stub(condition: isPath("/v1/initialize")) { _ in
                    calls += 1
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 500, headers: nil)
                }

                TestUtils.startStatsigAndWait(key: "client-key")
                expect(calls).to(equal(4))  // 1 + 3 retries
            }
        }
    }
}
