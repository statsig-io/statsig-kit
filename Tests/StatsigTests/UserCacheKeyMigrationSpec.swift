import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

class UserCacheKeyMigrationSpec: BaseSpec {

    override func spec() {
        super.spec()

        describe("UserCacheKeyMigration") {
            let key = "client-key"
            let user = StatsigUser(
                userID: "a_user",
                customIDs: ["groupID": "a_group", "teamID": "a_team"]
            )
            let cacheKey = UserCacheKey.from(StatsigOptions(), user, key)

            var defaults: MockDefaults!

            afterEach {
                Statsig.shutdown()
            }

            describe("when cache is empty") {
                beforeEach {
                    defaults = MockDefaults()
                    StatsigUserDefaults.defaults = defaults

                    _ = TestUtils.startWithResponseAndWait(
                        [
                            "feature_gates": [:],
                            "dynamic_configs": [:],
                            "layer_configs": [:],
                            "time": 123,
                            "has_updates": true,
                            "hash_used": "none",
                        ],
                        key,
                        user
                    )
                    Statsig.shutdown()
                    HTTPStubs.removeAllStubs()
                }

                it("saves values as full") {
                    let keys = defaults.getUserCaches().allKeys as? [String]
                    expect(keys).to(equal([cacheKey.full]))
                }
            }

            describe("when cache has v1 value") {
                beforeEach {
                    defaults = MockDefaults(data: [
                        InternalStore.localStorageKey: [
                            cacheKey.v1: [
                                "feature_gates": [
                                    "test_gate": [
                                        "name": "test_gate",
                                        "value": true,
                                        "rule_id": "a_rule_id",
                                        "id_type": "userID",
                                        "secondary_exposures": [],
                                    ]
                                ],
                                "dynamic_configs": [:],
                                "layer_configs": [:],
                                "time": 123,
                                "has_updates": true,
                                "hash_used": "none",
                            ]
                        ]
                    ])

                    StatsigUserDefaults.defaults = defaults

                    _ = TestUtils.startWithResponseAndWait(["has_updates": false], key, user)
                }

                it("saves values as full user hash and removes v1") {
                    let keys = defaults.getUserCaches().allKeys as? [String]
                    expect(keys).to(equal([cacheKey.full]))
                }

                it("gets the values that were migrated from v1") {
                    expect(Statsig.checkGate("test_gate")).to(beTrue())
                }
            }

            describe("when cache has v2 value") {
                beforeEach {
                    defaults = MockDefaults(data: [
                        InternalStore.localStorageKey: [
                            cacheKey.v2: [
                                "feature_gates": [
                                    "test_gate": [
                                        "name": "test_gate",
                                        "value": true,
                                        "rule_id": "a_rule_id",
                                        "id_type": "userID",
                                        "secondary_exposures": [],
                                    ]
                                ],
                                "dynamic_configs": [:],
                                "layer_configs": [:],
                                "time": 123,
                                "has_updates": true,
                                "hash_used": "none",
                            ]
                        ]
                    ])

                    StatsigUserDefaults.defaults = defaults

                    _ = TestUtils.startWithResponseAndWait(["has_updates": false], key, user)
                }

                it("saves values as full user hash and removes v2") {
                    let keys = defaults.getUserCaches().allKeys as? [String]
                    expect(keys).to(equal([cacheKey.full]))
                }

                it("gets the values were in cache") {
                    expect(Statsig.checkGate("test_gate")).to(beTrue())
                }
            }

            describe("when cache has full user hash key") {
                beforeEach {
                    defaults = MockDefaults(data: [
                        InternalStore.localStorageKey: [
                            cacheKey.full: [
                                "feature_gates": [
                                    "test_gate": [
                                        "name": "test_gate",
                                        "value": true,
                                        "rule_id": "a_rule_id",
                                        "id_type": "userID",
                                        "secondary_exposures": [],
                                    ]
                                ],
                                "dynamic_configs": [:],
                                "layer_configs": [:],
                                "time": 123,
                                "has_updates": true,
                                "hash_used": "none",
                            ]
                        ]
                    ])

                    StatsigUserDefaults.defaults = defaults

                    _ = TestUtils.startWithResponseAndWait(["has_updates": false], key, user)
                }

                it("saves values as full user hash") {
                    let keys = defaults.getUserCaches().allKeys as? [String]
                    expect(keys).to(equal([cacheKey.full]))
                }

                it("gets the values were in cache") {
                    expect(Statsig.checkGate("test_gate")).to(beTrue())
                }
            }
        }
    }
}
