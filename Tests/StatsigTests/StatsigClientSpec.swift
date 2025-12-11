import Foundation
import Nimble
import OHHTTPStubs
import Quick
import SwiftUI

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class StatsigClientSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("initializing Statsig") {
            beforeEach {
                TestUtils.clearStorage()
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
                TestUtils.clearStorage()
            }

            it("initializes with trailing closure") {
                var callbackCalled = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)

                let client = StatsigClient(sdkKey: "client-api-key", options: opts) { _ in
                    callbackCalled = true
                }

                expect(callbackCalled).toEventually(beTrue())
                expect(client.isInitialized()).toEventually(beTrue())
            }

            it("initializes with completion param") {
                var callbackCalled = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)

                let client = StatsigClient(
                    sdkKey: "client-api-key", options: opts,
                    completion: { _ in
                        callbackCalled = true
                    })

                expect(callbackCalled).toEventually(beTrue())
                expect(client.isInitialized()).toEventually(beTrue())
            }

            it("initializes with completionWithResult param") {
                var callbackCalled = false
                stub(condition: isHost(ApiHost)) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(disableDiagnostics: true)

                let client = StatsigClient(
                    sdkKey: "client-api-key", options: opts,
                    completionWithResult: { _ in
                        callbackCalled = true
                    })

                expect(callbackCalled).toEventually(beTrue())
                expect(client.isInitialized()).toEventually(beTrue())
            }

        }
    }
}
