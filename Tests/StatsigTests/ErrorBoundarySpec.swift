import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class ErrorBoundarySpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("ErrorBoundary") {

            var sdkExceptionsReceived = [[String: Any]]()
            var sdkExceptionRequests = [URLRequest]()

            beforeEach {
                sdkExceptionsReceived.removeAll()
                sdkExceptionRequests.removeAll()

                // Setup Event Exception
                stub(condition: isPath("/v1/sdk_exception")) { request in
                    sdkExceptionRequests.append(request)
                    sdkExceptionsReceived.append(request.statsig_body ?? [:])
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }
            }

            afterEach {
                HTTPStubs.removeAllStubs()
                Statsig.shutdown()
            }

            it("catches errors") {
                let errorBoundary = ErrorBoundary.boundary(
                    clientKey: "client-key", statsigOptions: StatsigOptions())
                expect {
                    errorBoundary.capture("ErrorBoundarySpec") { () throws in
                        throw StatsigError.unexpectedError("Test Error")
                    }
                }
                .toNot(throwError())
            }

            it("logs errors to sdk_exception") {
                let errorBoundary = ErrorBoundary.boundary(
                    clientKey: "client-key", statsigOptions: StatsigOptions())
                errorBoundary.capture("ErrorBoundarySpec") { () throws in
                    throw StatsigError.unexpectedError("Test Error 2")
                }
                expect(sdkExceptionsReceived.count).toEventually(beGreaterThanOrEqualTo(1))
            }

            it("uses the overridden api host for sdk_exception") {
                let errorBoundary = ErrorBoundary.boundary(
                    clientKey: "client-key",
                    statsigOptions: StatsigOptions(
                        sdkExceptionDiagnosticsURL: URL(
                            string: "http://api.override.com/v1/sdk_exception")))
                errorBoundary.capture("ErrorBoundarySpec") { () throws in
                    throw StatsigError.unexpectedError("Override API Error")
                }

                expect(sdkExceptionRequests.count).toEventually(beGreaterThanOrEqualTo(1))
                expect(sdkExceptionRequests.first?.url?.absoluteString)
                    .toEventually(equal("http://api.override.com/v1/sdk_exception"))
            }

            it("does not derive sdk_exception from initialization url") {
                let errorBoundary = ErrorBoundary.boundary(
                    clientKey: "client-key",
                    statsigOptions: StatsigOptions(
                        initializationURL: URL(string: "http://api.override.com/custom_path")))
                errorBoundary.capture("ErrorBoundarySpec") { () throws in
                    throw StatsigError.unexpectedError("Override URL Error")
                }

                expect(sdkExceptionRequests.count).toEventually(beGreaterThanOrEqualTo(1))
                expect(sdkExceptionRequests.first?.url?.absoluteString)
                    .toEventually(equal("https://statsigapi.net/v1/sdk_exception"))
            }

            it("logs statsig option to sdk_exception") {
                let errorBoundary = ErrorBoundary.boundary(
                    clientKey: "client-key",
                    statsigOptions: StatsigOptions(
                        initTimeout: 11,
                        disableCurrentVCLogging: true,
                        overrideStableID: "ErrorBoundarySpec",
                        initializeValues: nil,  // Default value
                        shutdownOnBackground: true,  // Default value
                        initializationURL: URL(string: "http://ErrorBoundarySpec/v1/initialize"),
                        sdkExceptionDiagnosticsURL: URL(
                            string: "http://ErrorBoundarySpec/v1/sdk_exception"),
                        evaluationCallback: { (_) -> Void in },
                        storageProvider: MockStorageProvider(),
                        overrideAdapter: OnDeviceEvalAdapter(
                            stringPayload:
                                "{\"feature_gates\":[],\"dynamic_configs\":[],\"layer_configs\":[],\"time\":0}"
                        )
                    )
                )
                errorBoundary.capture("ErrorBoundarySpec") { () throws in
                    throw StatsigError.unexpectedError("Test Error 3")
                }
                expect(sdkExceptionsReceived.count).toEventually(beGreaterThanOrEqualTo(1))
                guard
                    let sdkException = sdkExceptionsReceived.first,
                    let exceptionOptions = sdkException["statsigOptions"] as? [String: Any]
                else {
                    fail("No SDK exception received")
                    return
                }
                expect(exceptionOptions["disableCurrentVCLogging"] as? Bool)
                    .toEventually(equal(true))
                expect(exceptionOptions["initTimeout"] as? Double)
                    .toEventually(equal(11))
                expect(exceptionOptions["overrideStableID"] as? String)
                    .toEventually(equal("ErrorBoundarySpec"))
                expect(exceptionOptions["initializationURL"] as? String)
                    .toEventually(equal("http://ErrorBoundarySpec/v1/initialize"))
                expect(exceptionOptions["sdkExceptionDiagnosticsURL"] as? String)
                    .toEventually(equal("http://ErrorBoundarySpec/v1/sdk_exception"))
                expect(exceptionOptions["evaluationCallback"] as? String).toEventually(equal("set"))
                expect(exceptionOptions["storageProvider"] as? String).toEventually(equal("set"))
                expect(exceptionOptions["overrideAdapter"] as? String).toEventually(equal("set"))

                // Options with default values are not in the dictionary
                expect(exceptionOptions.keys.contains("shutdownOnBackground")).to(beFalse())
                // Optional options with nil value are not in the dictionary
                expect(exceptionOptions.keys.contains("initializeValues")).to(beFalse())
            }
        }
    }
}
