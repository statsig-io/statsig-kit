import Foundation
import Nimble
import Quick

@testable import Statsig

class StatsigUserSpec: BaseSpec {
    override func spec() {
        super.spec()

        let validJSONObject: [String: StatsigUserCustomTypeConvertible] =
            ["company": "Statsig", "YOE": 10.5, "alias": ["abby", "bob", "charlie"]]

        describe("creating a new StatsigUser") {
            it("is a valid empty user") {
                let validEmptyUser = StatsigUser()
                expect(validEmptyUser).toNot(beNil())
                expect(validEmptyUser.userID).to(beNil())
                expect(validEmptyUser.email).to(beNil())
                expect(validEmptyUser.country).to(beNil())
                expect(validEmptyUser.ip).to(beNil())
                expect(validEmptyUser.custom).to(beNil())
                expect(validEmptyUser.deviceEnvironment).toNot(beNil())
                expect(validEmptyUser.customIDs).to(beNil())
            }

            it("only return sdk related medatada if opt out non sdk metadata") {
                let validUserOptOutNonSdkMetadata = StatsigUser(optOutNonSdkMetadata: true)

                let deviceEnvironment = validUserOptOutNonSdkMetadata.deviceEnvironment
                expect(deviceEnvironment[StatsigMetadata.SDK_VERSION_KEY]).toNot(beNil())
                expect(deviceEnvironment[StatsigMetadata.SDK_TYPE_KEY]) == "ios-client"
                expect(deviceEnvironment[StatsigMetadata.SESSION_ID_KEY]).toNot(beNil())
                expect(deviceEnvironment[StatsigMetadata.STABLE_ID_KEY]).toNot(beNil())
                expect(deviceEnvironment.count) == 4
            }

            it("is a valid user with ID provided") {
                let validUserWithID = StatsigUser(userID: "12345")
                expect(validUserWithID).toNot(beNil())
                expect(validUserWithID.userID) == "12345"
                expect(validUserWithID.statsigEnvironment) == [:]
                expect(validUserWithID.toDictionary(forLogging: false).count) == 2
            }

            it("is a valid user with custom attribute") {
                let validUserWithCustom = StatsigUser(userID: "12345", custom: validJSONObject)
                expect(validUserWithCustom).toNot(beNil())
                expect(validUserWithCustom.userID) == "12345"

                let customDict = validUserWithCustom.custom!
                expect(customDict.count) == 3
                expect(customDict["company"] as? String) == "Statsig"
                expect(customDict["YOE"] as? Double) == 10.5
                expect(customDict["alias"] as? [String]) == ["abby", "bob", "charlie"]
            }

            it("drops private attributes for logging") {
                let userWithPrivateAttributes = StatsigUser(
                    userID: "12345", privateAttributes: validJSONObject)
                let user = StatsigUser(userID: "12345")

                let userWithPrivateDict = userWithPrivateAttributes.toDictionary(forLogging: true)
                expect(userWithPrivateDict.count) == user.toDictionary(forLogging: true).count
                expect(userWithPrivateDict["privateAttributes"]).to(beNil())
            }

            it("keeps customIDs in the json") {
                let user = StatsigUser(userID: "12345", customIDs: ["company_id": "998877"])
                let json = user.toDictionary(forLogging: false)
                expect(NSDictionary(dictionary: json["customIDs"] as! [String: String])).to(
                    equal(NSDictionary(dictionary: ["company_id": "998877"])))
            }
        }
    }
}
