import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class UserCacheKeySpec: BaseSpec {

    override func spec() {
        super.spec()

        let options = StatsigOptions()

        describe("UserCacheKey") {
            it("gets the same keys for identical users") {
                let firstUser = StatsigUser(userID: "a-user")
                let secondUser = StatsigUser(userID: "a-user")

                let firstKey = UserCacheKey.from(options, firstUser, "some-key")
                let secondKey = UserCacheKey.from(options, secondUser, "some-key")

                expect(firstKey.v1).to(equal(secondKey.v1))
                expect(firstKey.v2).to(equal(secondKey.v2))
            }

            it("gets different keys for different users") {
                let firstUser = StatsigUser(userID: "a-user")
                let secondUser = StatsigUser(userID: "b-user")

                let firstKey = UserCacheKey.from(options, firstUser, "some-key")
                let secondKey = UserCacheKey.from(options, secondUser, "some-key")

                expect(firstKey.v1).notTo(equal(secondKey.v1))
                expect(firstKey.v2).notTo(equal(secondKey.v2))
            }

            it("gets different v2 but same v1 for different sdk keys") {
                let firstUser = StatsigUser(userID: "a-user")
                let secondUser = StatsigUser(userID: "a-user")

                let firstKey =
                    UserCacheKey
                    .from(options, firstUser, "some-key")
                let secondKey =
                    UserCacheKey
                    .from(options, secondUser, "some-other-key")

                expect(firstKey.v1).to(equal(secondKey.v1))
                expect(firstKey.v2).notTo(equal(secondKey.v2))
            }

            it("gets the same values for null users") {
                let firstUser = StatsigUser()
                let secondUser = StatsigUser()

                let firstKey =
                    UserCacheKey
                    .from(options, firstUser, "some-key")
                let secondKey =
                    UserCacheKey
                    .from(options, secondUser, "some-key")

                expect(firstKey.v1).to(equal(secondKey.v1))
                expect(firstKey.v2).to(equal(secondKey.v2))
            }

            it("gets the same cache key regardless of custom id order") {
                let firstUser = StatsigUser(customIDs: ["a": "1", "b": "2"])
                let secondUser = StatsigUser(customIDs: ["b": "2", "a": "1"])

                let firstKey =
                    UserCacheKey
                    .from(options, firstUser, "some-key")
                let secondKey =
                    UserCacheKey
                    .from(options, secondUser, "some-key")

                // its a known bug that v1 didn't handle this case

                expect(firstKey.v2).to(equal(secondKey.v2))
            }

            it("uses custom cache key when provided") {
                let sdkKey = "client-key"
                let user = StatsigUser(customIDs: ["a": "1", "b": "2"])

                let custom = "mine"
                let opts = StatsigOptions(customCacheKey: { _, _ in custom })
                let key = UserCacheKey.from(opts, user, sdkKey)

                expect(key.v1).to(equal(custom))
                expect(key.v2).to(equal(custom))
            }
        }
    }
}
