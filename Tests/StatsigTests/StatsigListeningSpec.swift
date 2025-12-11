import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

func goodStub() {
    stub(condition: isHost(ApiHost)) { req in
        return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
    }
}

func badStub() {
    stub(condition: isHost(ApiHost)) { req in
        return HTTPStubsResponse(jsonObject: [:], statusCode: 500, headers: nil)
    }
}

class StatsigListeningSpec: BaseSpec {
    class TestListener: StatsigListening {
        var onInitializedCalled = false
        var onInitializedError: String?

        var onUserUpdatedCalled = false
        var onUserUpdatedError: String?

        var onInitializedWithResultCalled = false
        var onInitializedWithResultError: StatsigClientError?

        var onUserUpdatedWithResultCalled = false
        var onUserUpdatedWithResultError: StatsigClientError?

        func onInitialized(_ error: String?) {
            onInitializedCalled = true
            onInitializedError = error
        }

        func onUserUpdated(_ error: String?) {
            onUserUpdatedCalled = true
            onUserUpdatedError = error
        }

        func onInitializedWithResult(_ error: StatsigClientError?) {
            onInitializedWithResultCalled = true
            onInitializedWithResultError = error
        }

        func onUserUpdatedWithResult(_ error: StatsigClientError?) {
            onUserUpdatedWithResultCalled = true
            onUserUpdatedWithResultError = error
        }
    }

    class PartialDeprecatedTestListener: StatsigListening {
        var onInitializedCalled = false
        var onInitializedError: String?

        var onUserUpdatedCalled = false
        var onUserUpdatedError: String?

        func onInitialized(_ error: String?) {
            onInitializedCalled = true
            onInitializedError = error
        }

        func onUserUpdated(_ error: String?) {
            onUserUpdatedCalled = true
            onUserUpdatedError = error
        }
    }

    class PartialWithResultTestListener: StatsigListening {

        var onInitializedWithResultCalled = false
        var onInitializedWithResultError: StatsigClientError?

        var onUserUpdatedWithResultCalled = false
        var onUserUpdatedWithResultError: StatsigClientError?

        func onInitializedWithResult(_ error: StatsigClientError?) {
            onInitializedWithResultCalled = true
            onInitializedWithResultError = error
        }

        func onUserUpdatedWithResult(_ error: StatsigClientError?) {
            onUserUpdatedWithResultCalled = true
            onUserUpdatedWithResultError = error
        }
    }

    override func spec() {
        super.spec()

        let opts = StatsigOptions(disableDiagnostics: true)

        beforeEach {
            TestUtils.clearStorage()
        }

        afterEach {
            HTTPStubs.removeAllStubs()
            Statsig.shutdown()
            TestUtils.clearStorage()
        }

        describe("checking if initialized") {
            it("returns true when initialized") {
                goodStub()

                expect(Statsig.isInitialized()).to(beFalse())
                var called = false
                let opts = StatsigOptions(disableDiagnostics: true)
                Statsig.initialize(sdkKey: "client-key", options: opts) { _ in
                    called = true
                }
                expect(called).toEventually(beTrue())
                expect(Statsig.isInitialized()).to(beTrue())
            }

            it("returns true when initialized with deprecated function") {
                goodStub()

                expect(Statsig.isInitialized()).to(beFalse())
                var called = false
                let opts = StatsigOptions(disableDiagnostics: true)
                Statsig.initialize(sdkKey: "client-key", options: opts) { _ in
                    called = true
                }
                expect(called).toEventually(beTrue())
                expect(Statsig.isInitialized()).to(beTrue())
            }
        }

        describe("listening to initialize callbacks") {
            it("responds with errors") {
                badStub()

                let listener = TestListener()
                let opts = StatsigOptions(disableDiagnostics: true)
                Statsig.initialize(sdkKey: "client-key", options: opts)
                Statsig.addListener(listener)

                expect(listener.onInitializedError).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
                expect(listener.onInitializedWithResultError?.message).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
            }

            it("responds without errors") {
                goodStub()

                let listener = TestListener()

                Statsig.initialize(sdkKey: "client-key", options: opts)
                Statsig.addListener(listener)

                expect(listener.onInitializedCalled).toEventually(beTrue())
                expect(listener.onInitializedWithResultCalled).toEventually(beTrue())
                expect(listener.onInitializedError).to(beNil())
                expect(listener.onInitializedWithResultError).to(beNil())
            }

            it("notifies multiple users") {
                goodStub()

                let listener1 = TestListener()
                let listener2 = TestListener()

                Statsig.initialize(sdkKey: "client-key", options: opts)
                Statsig.addListener(listener1)
                Statsig.addListener(listener2)

                expect(listener1.onInitializedCalled).toEventually(beTrue())
                expect(listener2.onInitializedCalled).toEventually(beTrue())
                expect(listener1.onInitializedWithResultCalled).toEventually(beTrue())
                expect(listener2.onInitializedWithResultCalled).toEventually(beTrue())
            }

            it("accepts partial listeners") {
                goodStub()

                let deprecatedListener = PartialDeprecatedTestListener()
                let resultListener = PartialWithResultTestListener()

                Statsig.initialize(sdkKey: "client-key", options: opts)
                Statsig.addListener(deprecatedListener)
                Statsig.addListener(resultListener)

                expect(deprecatedListener.onInitializedCalled).toEventually(beTrue())
                expect(resultListener.onInitializedWithResultCalled).toEventually(beTrue())
            }

            it("responds immediately if initializing has previously completed") {
                goodStub()
                var initialized = false
                Statsig.initialize(sdkKey: "client-key", options: opts) { _ in
                    initialized = true
                }

                expect(initialized).toEventually(beTrue())
                let listener = TestListener()
                Statsig.addListener(listener)
                expect(listener.onInitializedCalled).to(beTrue())
                expect(listener.onInitializedWithResultCalled).to(beTrue())
            }

            it("responds immediately with error if initializing has previously completed") {
                badStub()
                var errorMessage: String?
                Statsig.initialize(sdkKey: "client-key", options: opts) { err in
                    errorMessage = err?.message
                }

                expect(errorMessage).toEventuallyNot(beNil())
                let listener = TestListener()
                Statsig.addListener(listener)
                expect(listener.onInitializedCalled).to(beTrue())
                expect(listener.onInitializedWithResultCalled).to(beTrue())
                expect(listener.onInitializedError).to(equal(errorMessage))
                expect(listener.onInitializedWithResultError?.message).to(equal(errorMessage))
            }

            it("can add listeners before start is called") {
                goodStub()

                let listener = TestListener()
                Statsig.addListener(listener)

                Statsig.initialize(sdkKey: "client-key", options: opts)

                expect(listener.onInitializedCalled).toEventually(beTrue())
                expect(listener.onInitializedWithResultCalled).toEventually(beTrue())
                expect(listener.onInitializedError).to(beNil())
                expect(listener.onInitializedWithResultError).to(beNil())
            }
        }

        describe("listening to background sync callbacks") {
            beforeEach {
                goodStub()
                stub(condition: isHost("AutoUpdateSpec")) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 200, headers: nil)
                }

                let opts = StatsigOptions(
                    enableAutoValueUpdate: true,
                    autoValueUpdateIntervalSec: 0.01,
                    api: "http://AutoUpdateSpec"
                )

                var initialized = false
                Statsig.initialize(sdkKey: "client-key", options: opts) { _ in
                    initialized = true
                }
                expect(initialized).toEventually(beTrue())
            }

            it("triggers the listener after auto-update interval") {
                let listener = TestListener()
                Statsig.addListener(listener)

                expect(listener.onUserUpdatedCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedWithResultCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedError).to(beNil())
                expect(listener.onUserUpdatedWithResultError).to(beNil())
            }

            it("triggers the listener with error") {
                stub(condition: isHost("AutoUpdateSpec")) { req in
                    return HTTPStubsResponse(jsonObject: [:], statusCode: 500, headers: nil)
                }

                let listener = TestListener()
                Statsig.addListener(listener)

                expect(listener.onUserUpdatedCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedWithResultCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedError).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
                expect(listener.onUserUpdatedWithResultError?.message).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
            }
        }

        describe("listening to updateUserWithResult callbacks") {
            beforeEach {
                goodStub()

                var initialized = false
                Statsig.initialize(sdkKey: "client-key", options: opts) { _ in
                    initialized = true
                }
                expect(initialized).toEventually(beTrue())
            }

            it("responds with errors") {
                badStub()

                let listener = TestListener()
                Statsig.addListener(listener)
                Statsig.updateUserWithResult(StatsigUser())

                expect(listener.onUserUpdatedError).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
                expect(listener.onUserUpdatedWithResultError?.message).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
            }

            it("responds without errors") {
                goodStub()

                let listener = TestListener()
                Statsig.addListener(listener)
                Statsig.updateUserWithResult(StatsigUser())

                expect(listener.onUserUpdatedCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedWithResultCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedError).to(beNil())
                expect(listener.onUserUpdatedWithResultError).to(beNil())
            }

            it("responds with errors") {
                badStub()

                let listener = TestListener()
                Statsig.addListener(listener)
                Statsig.updateUserWithResult(StatsigUser())

                expect(listener.onUserUpdatedError).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
                expect(listener.onUserUpdatedWithResultError?.message).toEventually(
                    contain("An error occurred during fetching values for the user. 500"))
            }

            it("responds without errors with deprecated function") {
                goodStub()

                let listener = TestListener()
                Statsig.addListener(listener)
                Statsig.updateUserWithResult(StatsigUser())

                expect(listener.onUserUpdatedCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedWithResultCalled).toEventually(beTrue())
                expect(listener.onUserUpdatedError).to(beNil())
                expect(listener.onUserUpdatedWithResultError).to(beNil())
            }
        }
    }
}
