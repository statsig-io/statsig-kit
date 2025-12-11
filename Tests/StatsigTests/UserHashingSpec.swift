import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

let userA = StatsigUser(
    userID: "user-a",
    email: "user-a@statsig.io",
    ip: "1.2.3.4",
    country: "US",
    locale: "en_US",
    appVersion: "3.2.1",
    custom: ["isVerified": true, "hasPaid": false],
    privateAttributes: ["age": 34, "secret": "shhh"],
    customIDs: ["workID": "employee-a", "projectID": "project-a"]
)

let userAAgain = StatsigUser(
    userID: "user-a",
    email: "user-a@statsig.io",
    ip: "1.2.3.4",
    country: "US",
    locale: "en_US",
    appVersion: "3.2.1",
    custom: ["hasPaid": false, "isVerified": true],
    privateAttributes: ["secret": "shhh", "age": 34],
    customIDs: ["projectID": "project-a", "workID": "employee-a"]
)

let userB = StatsigUser(
    userID: "user-b",
    email: "user-b@statsig.io",
    ip: "5.6.7.8",
    country: "NZ",
    locale: "en_NZ",
    appVersion: "8.7.6",
    custom: ["hasPaid": true, "isVerified": false],
    privateAttributes: ["secret": "booo", "age": 29],
    customIDs: ["workID": "employee-b", "projectID": "project-b"]
)

class UserHashingSpec: BaseSpec {
    override func spec() {
        super.spec()

        describe("User Hashing") {

            it("gets the same has for identical users") {
                expect(userA.getFullUserHash()).to(equal(userAAgain.getFullUserHash()))
            }

            it("gets different hashes for different users") {
                expect(userA.getFullUserHash()).notTo(equal(userB.getFullUserHash()))
            }
        }
    }
}
