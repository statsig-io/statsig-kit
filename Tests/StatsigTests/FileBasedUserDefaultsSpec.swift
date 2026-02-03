import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class FileBasedUserDefaultsSpec: BaseSpec {

    override func spec() {
        super.spec()

        describe("FileBasedUserDefaults") {
            describe("strings") {
                it("writes and reads") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set("Foo", forKey: "Bar")
                    expect(defaults.string(forKey: "Bar")).to(equal("Foo"))
                }

                it("writes and reads across sessions") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set("Foo", forKey: "Bar")

                    expect(FileBasedUserDefaults().string(forKey: "Bar")).toEventually(equal("Foo"))
                }
            }

            describe("dictionaries") {
                it("writes and reads") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set(["A": "B"], forKey: "Bar")
                    expect(defaults.dictionary(forKey: "Bar") as? [String: String]).to(
                        equal(["A": "B"]))
                }

                it("writes and reads across sessions") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set(["A": "B"], forKey: "Bar")

                    expect(FileBasedUserDefaults().dictionary(forKey: "Bar") as? [String: String])
                        .toEventually(
                            equal(["A": "B"]))
                }
            }

            describe("arrays") {
                it("writes and reads") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set(["Foo"], forKey: "Bar")
                    expect(defaults.array(forKey: "Bar") as? [String]).to(equal(["Foo"]))
                }

                it("writes and reads across sessions") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set(["Foo"], forKey: "Bar")

                    expect(FileBasedUserDefaults().array(forKey: "Bar") as? [String]).toEventually(
                        equal(["Foo"]))
                }
            }

            describe("removing values") {
                it("removes values") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set("Foo", forKey: "Bar")
                    defaults.removeObject(forKey: "Bar")
                    expect(defaults.string(forKey: "Bar")).to(beNil())
                }

                it("removes values across sessions") {
                    let defaults = FileBasedUserDefaults()
                    defaults.set("Foo", forKey: "Bar")
                    defaults.removeObject(forKey: "Bar")

                    expect(FileBasedUserDefaults().string(forKey: "Bar")).toEventually(beNil())
                }
            }
        }
    }
}
