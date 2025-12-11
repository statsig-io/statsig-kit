import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class ThreadsSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("Running a block with ensureMainThread") {

            it("runs synchronously when called from the main thread") {
                var called = false
                ensureMainThread {
                    called = true
                }
                expect(called).to(equal(true))
            }

            it("runs async when called from another thread") {
                var called = false

                // Freeze main thread until the background work is done
                TestUtils.freezeThreadUntilAsyncDone {
                    // Queue main thread execution
                    ensureMainThread {
                        expect(Thread.isMainThread).to(equal(true))
                        called = true
                    }

                    // Since the main thread is blocked, this should still be false
                    expect(called).to(equal(false))
                }

                expect(called).toEventually(equal(true))
            }
        }
    }
}
