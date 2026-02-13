import Foundation
import Nimble
import Quick

@testable import Statsig

final class InternalStoreMultiFileSpec: BaseSpec {

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

            var tempDir: URL?
            var originalURL = UserPayloadStore.rootDirectoryURL

            func userPayloadFileURL(_ sdkKey: String, _ cacheKey: UserCacheKey) -> URL? {
                return tempDir?
                    .appendingPathComponent(sdkKey)
                    .appendingPathComponent("user-payload")
                    .appendingPathComponent(cacheKey.fullUserHash)
            }

            func legacyPayloadFileURL(_ filename: String) -> URL? {
                return tempDir?
                    .appendingPathComponent("_legacy")
                    .appendingPathComponent("user-payload")
                    .appendingPathComponent(filename)
            }

            func legacyPayload(_ key: String) -> [String: Any]? {
                let legacyDir =
                    tempDir?
                    .appendingPathComponent("_legacy")
                    .appendingPathComponent("user-payload")

                if let payload = UserPayloadStore.read(
                    url: legacyDir?.appendingPathComponent(key)
                ) {
                    return payload
                }

                return nil
            }

            beforeSuite {
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("statsig-cache")
                let uniqueDirectoryName = UUID().uuidString
                let tempDirectoryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(uniqueDirectoryName, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    fail("Failed to create dir: \(error)")
                }

                tempDir = dir
                originalURL = UserPayloadStore.rootDirectoryURL
                UserPayloadStore.rootDirectoryURL = dir
            }

            afterSuite {
                if let originalURL = originalURL,
                    UserPayloadStore.rootDirectoryURL != originalURL
                {
                    UserPayloadStore.rootDirectoryURL = originalURL
                }
                if let tempDir = tempDir {
                    try? FileManager.default.removeItem(at: tempDir)
                }
            }

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

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
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

                    waitUntil { done in
                        store.saveValues(
                            StatsigSpec.mockUpdatedUserValues, keyB, userB.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keyA)!))
                        .toEventuallyNot(beNil())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keyB)!))
                        .toEventuallyNot(beNil())

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

                    waitUntil { done in
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

                    waitUntil { done in
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

                    waitUntil { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())

                    if let fileURL = userPayloadFileURL(sdkKey, cacheKey) {
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

                    waitUntil { done in
                        store.saveValues(
                            StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                        ) {
                            done()
                        }
                    }

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())

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

            describe("migration") {

                beforeEach {
                    UserPayloadStore.migrationStatus = .none
                }

                afterEach {
                    UserPayloadStore.migrationStatus = .none
                }

                it("reads from userDefaults and migrates when no user-scoped file exists") {
                    let user = StatsigUser(userID: "user_a")
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    StatsigUserDefaults.defaults.setDictionarySafe(
                        [cacheKey.fullUserWithSDKKey: StatsigSpec.mockUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, user, options: options)

                    store.migrateIfNeeded()

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .toEventually(beNil())
                }

                it("migrates existing UserDefaults payloads into user-scoped files") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let otherSdkKey = "client-other-key"

                    let keyA = UserCacheKey.from(options, userA, sdkKey)
                    let keyB = UserCacheKey.from(options, userB, otherSdkKey)

                    StatsigUserDefaults.defaults.setDictionarySafe(
                        [
                            keyA.fullUserWithSDKKey: StatsigSpec.mockUserValues,
                            keyB.fullUserWithSDKKey: StatsigSpec.mockUpdatedUserValues,
                        ],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let storeA = InternalStore(sdkKey, userA, options: options)

                    storeA.migrateIfNeeded()

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keyA)!))
                        .toEventuallyNot(beNil())
                    expect(try? Data(contentsOf: userPayloadFileURL(otherSdkKey, keyB)!))
                        .toEventuallyNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .toEventually(beNil())
                }

                it("migrates v2 keys from UserDefaults payloads and reads them") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let cacheKeyB = UserCacheKey.from(options, userB, sdkKey)

                    StatsigUserDefaults.defaults.setDictionarySafe(
                        [cacheKeyB.v2: StatsigSpec.mockUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, userA, options: options)

                    store.migrateIfNeeded()

                    expect(legacyPayload(cacheKeyB.v2)).toEventuallyNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .toEventually(beNil())
                }

                it("migrates v1 keys from UserDefaults payloads and reads them") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let cacheKeyB = UserCacheKey.from(options, userB, sdkKey)

                    StatsigUserDefaults.defaults.setDictionarySafe(
                        [cacheKeyB.v1: StatsigSpec.mockUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, userA, options: options)

                    store.migrateIfNeeded()

                    expect(legacyPayload(cacheKeyB.v1)).toEventuallyNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .toEventually(beNil())
                }
            }

            describe("concurrency") {
                // TODO
            }

        }
    }
}
