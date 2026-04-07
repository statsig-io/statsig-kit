import Foundation
import Nimble
import Quick

@testable import Statsig

final class LockedValueSpec: BaseSpec {
    private final class TestLockedValue {
        @LockedValue
        var count: Double = 0
        @LockedValue
        var dict: [String: Int] = [:]
    }

    override func spec() {
        super.spec()

        describe("LockedValue") {
            it("supports plain get and set") {
                let obj = TestLockedValue()

                expect(obj.count).to(equal(0))

                obj.count = 2
                expect(obj.count).to(equal(2))
            }

            it("preserves mutating operations on value types") {
                let obj = TestLockedValue()

                obj.count += 1
                expect(obj.count).to(equal(1))

                obj.dict["a"] = 1
                obj.dict["a", default: 0] += 1
                expect(obj.dict["a"]).to(equal(2))
            }

            it("supports compound atomic updates with withLock") {
                let obj = TestLockedValue()

                let result = obj.$dict.withLock { dict in
                    dict["a", default: 0] += 1
                    dict["a", default: 0] += 1
                    return dict["a"]
                }

                expect(result).to(equal(2))
                expect(obj.dict["a"]).to(equal(2))
            }

            it("does not lose concurrent mutations protected by withLock") {
                let obj = TestLockedValue()
                let group = DispatchGroup()
                let queue = DispatchQueue.global(qos: .userInitiated)

                for _ in 0..<10_000 {
                    group.enter()
                    queue.async {
                        obj.$count.withLock { $0 += 1 }
                        group.leave()
                    }
                }

                expect(group.wait(timeout: .now() + 5)).to(equal(.success))
                expect(obj.count).to(equal(10_000))
            }

            it("does not lose concurrent mutations") {
                let obj = TestLockedValue()
                let group = DispatchGroup()
                let queue = DispatchQueue.global(qos: .userInitiated)

                for i in 0..<1000 {
                    let key = "key_\(i % 10)"
                    group.enter()
                    queue.async {
                        obj.count += 1
                        obj.dict[key, default: 0] += 1
                        group.leave()
                    }
                }

                expect(group.wait(timeout: .now() + 5)).to(equal(.success))
                expect(obj.count).to(equal(1000))
                for i in 0..<10 {
                    expect(obj.dict["key_\(i % 10)"]).to(equal(100))
                }
            }
        }
    }
}
