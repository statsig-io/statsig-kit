import Foundation
import Nimble
import Quick

@testable import Statsig

final class InternalStoreMultiFileSpec: BaseSpec {
    private func userPayloadFileURL(_ sdkKey: String, _ cacheKey: UserCacheKey) -> URL? {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("statsig-cache")
            .appendingPathComponent(sdkKey)
            .appendingPathComponent("user-payload")
            .appendingPathComponent(cacheKey.fullUserHash)
    }

    private func cacheIsEmpty(_ cache: [String: Any]) -> Bool {
        return
            (cache[InternalStore.gatesKey] as? [String: Any])?.count == 0
            && (cache[InternalStore.configsKey] as? [String: Any])?.count == 0
            && (cache[InternalStore.stickyExpKey] as? [String: Any])?.count == 0
            && (cache["time"] as? Int) == 0
    }

    override func spec() {
        super.spec()

        describe("InternalStore multi-file storage") {
            let sdkKey = "client-api-key"
            let options = StatsigOptions()
            var defaults: MockDefaults!

            beforeEach {
                StorageService.useMultiFileStorage = true
                defaults = MockDefaults(data: [:])
                StatsigUserDefaults.defaults = defaults
                TestUtils.clearStorage()
            }

            afterEach {
                TestUtils.clearStorage()
                StorageService.useMultiFileStorage = false
            }

            describe("persistence") {
                it("writes a payload to a user-scoped file") {
                    let user = StatsigUser(userID: "user_a")
                    let store = InternalStore(sdkKey, user, options: options)
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    waitUntil { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: self.userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())
                }

                it("reads the correct payload after updating the users") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")

                    let store = InternalStore(sdkKey, userA, options: options)
                    let keyA = UserCacheKey.from(options, userA, sdkKey)
                    let keyB = UserCacheKey.from(options, userB, sdkKey)

                    waitUntil { done in
                        store.saveValues(StatsigSpec.mockUserValues, keyA, userA.getFullUserHash())
                        {
                            done()
                        }
                    }

                    store.updateUser(userB)
                    skipFrame()

                    waitUntil(timeout: .seconds(1)) { done in
                        store.saveValues(
                            StatsigSpec.mockUpdatedUserValues, keyB, userB.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: self.userPayloadFileURL(sdkKey, keyA)!))
                        .toEventuallyNot(
                            beNil(),
                            timeout: .seconds(2)
                        )
                    expect(try? Data(contentsOf: self.userPayloadFileURL(sdkKey, keyB)!))
                        .toEventuallyNot(
                            beNil(),
                            timeout: .seconds(2)
                        )

                    let reloadedA = InternalStore(sdkKey, userA, options: options)
                    let reloadedB = InternalStore(sdkKey, userB, options: options)

                    expect(reloadedA.checkGate(forName: "gate_name_1").value).to(beFalse())
                    expect(reloadedB.checkGate(forName: "new_gate_name_1").value).to(beTrue())
                }

                it("reuses the cached values if no IDs changed during update") {
                    let user = StatsigUser(userID: "user_a")
                    let updatedUser = StatsigUser(
                        userID: "user_a",
                        email: "new_email@example.com",
                        country: "US"
                    )

                    let initialKey = UserCacheKey.from(options, user, sdkKey)
                    let updatedKey = UserCacheKey.from(options, updatedUser, sdkKey)
                    expect(updatedKey.v2).to(equal(initialKey.v2))

                    let store = InternalStore(sdkKey, user, options: options)

                    waitUntil(timeout: .seconds(1)) { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, initialKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())

                    store.updateUser(updatedUser)
                    skipFrame()

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())
                    expect(store.checkGate(forName: "gate_name_1").value).to(beFalse())
                }

                it("doesn't reuse the cached values if IDs changed during update") {
                    let user = StatsigUser(userID: "user_a")
                    let updatedUser = StatsigUser(
                        userID: "user_b",
                        email: "new_email@example.com",
                        country: "US"
                    )

                    let initialKey = UserCacheKey.from(options, user, sdkKey)
                    let updatedKey = UserCacheKey.from(options, updatedUser, sdkKey)
                    expect(updatedKey.v2).toNot(equal(initialKey.v2))

                    let store = InternalStore(sdkKey, user, options: options)

                    waitUntil(timeout: .seconds(1)) { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, initialKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())

                    store.updateUser(updatedUser)
                    skipFrame()

                    expect(store.checkGate(forName: "gate_name_2").value).to(beFalse())
                    expect(store.checkGate(forName: "gate_name_1").value).to(beFalse())
                }

                it("is resilient to a missing user file") {
                    let user = StatsigUser(userID: "user_a")
                    let store = InternalStore(sdkKey, user, options: options)
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    waitUntil(timeout: .seconds(1)) { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: self.userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(
                            beNil(),
                            timeout: .seconds(2)
                        )

                    if let fileURL = self.userPayloadFileURL(sdkKey, cacheKey) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }

                    let reloaded = InternalStore(sdkKey, user, options: options)
                    expect(self.cacheIsEmpty(reloaded.cache.userCache)).to(beTrue())
                    expect(reloaded.checkGate(forName: "gate_name_1").value).to(beFalse())
                }

                it("is resilient to a corrupted user file") {
                    let user = StatsigUser(userID: "user_a")
                    let store = InternalStore(sdkKey, user, options: options)
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    waitUntil(timeout: .seconds(1)) { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: self.userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(
                            beNil(),
                            timeout: .seconds(2)
                        )

                    if let dir = store.storageService.userPayload.directoryURL {
                        try? FileManager.default.createDirectory(
                            at: dir,
                            withIntermediateDirectories: true
                        )
                        let fileURL = dir.appendingPathComponent(cacheKey.fullUserHash)
                        let garbage = "not-json".data(using: .utf8)!
                        try? garbage.write(to: fileURL)
                    }

                    let reloaded = InternalStore(sdkKey, user, options: options)
                    expect(self.cacheIsEmpty(reloaded.cache.userCache)).to(beTrue())
                    expect(reloaded.checkGate(forName: "gate_name_1").value).to(beFalse())
                }

                // TODO: Validate that it can re-use storage from a different user
            }

            // TODO: Future PR
            describe("limits") {
                pending("deletes older user payloads once they reach a global limit") {}
            }

            // TODO: Future PR
            describe("migration") {
                pending("reads from userDefaults if no user-scoped file doesn't exist") {}
                // maybe: doesn't reads from userDefaults if the user-scoped file for the current user exists"
                // maybe: doesn't reads from userDefaults if the user-scoped file for another user exists"

                pending("migrates existing UserDefaults payloads into user-scoped files") {}
                // TODO: assert that userdefaults has no user payload after migration

                pending("migrates v2 keys from UserDefaults payloads, reads them ok") {}
                // TODO: assert that userdefaults has no user payload after migration

                pending("migrates v1 keys from UserDefaults payloads, reads them ok") {}
                // TODO: assert that userdefaults has no user payload after migration
            }

            describe("concurrency") {
                // TODO
            }

        }
    }
}
