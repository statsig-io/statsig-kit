import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class CompletionCallbackRaceSpec: BaseSpec {
    override func spec() {
        super.spec()

        let user = StatsigUser(userID: "jkw")
        let opts = StatsigOptions(initTimeout: 0.01, disableDiagnostics: true)

        var client: StatsigClient?

        describe("CompletionCallbackRace") {
            beforeEach {
                stub(condition: isPath("/v1/initialize")) { request in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                        .responseTime(0.01)
                }
            }

            it("invalidates previous timers") {
                for _ in 0..<10 {
                    var errorCode: StatsigClientErrorCode?
                    var calls = 0
                    waitUntil { done in
                        client = StatsigClient(sdkKey: "client-key", user: user, options: opts) {
                            error in
                            errorCode = error?.code
                            calls += 1
                            done()
                        }
                    }

                    expect(client).toNot(beNil())
                    expect(errorCode).to(equal(StatsigClientErrorCode.initTimeoutExpired))
                    expect(calls).toEventually(equal(1))
                }

            }
        }
    }
}
