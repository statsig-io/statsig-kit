import Foundation
import Nimble
import OHHTTPStubs
import Quick
import XCTest

@testable import Statsig

final class PrintHandlerSpec: BaseSpec {
    override func spec() {
        super.spec()

        beforeEach {
            PrintHandler.reset()
        }

        describe("PrintHandler") {
            it("accepts custom print handlers") {
                var receivedMessages: [String] = []

                PrintHandler.setPrintHandler({ message in
                    receivedMessages.append(message)
                })

                PrintHandler.log("Test message 1")
                PrintHandler.log("Test message 2")

                expect(receivedMessages.count).to(equal(2))
                expect(receivedMessages[0]).to(equal("Test message 1"))
                expect(receivedMessages[1]).to(equal("Test message 2"))
            }

            it("warns about handler override") {
                var messages1: [String] = []
                var messages2: [String] = []

                PrintHandler.setPrintHandler({ message in
                    messages1.append(message)
                })

                PrintHandler.setPrintHandler({ message in
                    messages2.append(message)
                })

                PrintHandler.log("Test message")

                expect(messages1.count).to(equal(2))
                expect(messages1[0]).to(contain("Warning"))
                expect(messages1[1]).to(equal("Test message"))

                expect(messages2).to(beEmpty())
            }
        }
    }
}
