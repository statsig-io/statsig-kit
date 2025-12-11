import Foundation
import Nimble
import Quick

@testable import Statsig

class ComparisonSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("compares simple versions correctly") {
            let smaller = JsonValue("25.45")
            let bigger = JsonValue("25.46")
            it("comparing distict versions") {
                expect(Comparison.versions(smaller, bigger, "version_eq"))
                    .to(equal(false))
                expect(Comparison.versions(smaller, bigger, "version_neq"))
                    .to(equal(true))

                expect(Comparison.versions(smaller, bigger, "version_gt"))
                    .to(equal(false))
                expect(Comparison.versions(smaller, bigger, "version_gte"))
                    .to(equal(false))

                expect(Comparison.versions(smaller, bigger, "version_lt"))
                    .to(equal(true))
                expect(Comparison.versions(smaller, bigger, "version_lte"))
                    .to(equal(true))
            }

            it("comparing identical versions") {
                expect(Comparison.versions(smaller, smaller, "version_eq"))
                    .to(equal(true))
                expect(Comparison.versions(smaller, smaller, "version_neq"))
                    .to(equal(false))

                expect(Comparison.versions(smaller, smaller, "version_gt"))
                    .to(equal(false))
                expect(Comparison.versions(smaller, smaller, "version_gte"))
                    .to(equal(true))

                expect(Comparison.versions(smaller, smaller, "version_lt"))
                    .to(equal(false))
                expect(Comparison.versions(smaller, smaller, "version_lte"))
                    .to(equal(true))
            }
        }
    }
}
