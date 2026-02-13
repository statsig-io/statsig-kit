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
            var originalURL = UserPayloadStore.defaultRootDirURL

            func userPayloadFileURL(_ sdkKey: String, _ cacheKey: UserCacheKey) -> URL? {
                return UserPayloadStore.getSDKKeyDirURL(tempDir, sdkKey)?
                    .appendingPathComponent(cacheKey.fullUserHash)
            }

            func legacyPayloadFileURL(_ filename: String) -> URL? {
                return tempDir?
                    .appendingPathComponent("_legacy")
                    .appendingPathComponent("user-payload")
                    .appendingPathComponent(filename)
            }

            func getIndexFileURL(_ sdkKey: String) -> URL? {
                return UserPayloadStore.getIndexFileURL(tempDir, sdkKey)
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

            func makePayload(withTimestamp timestamp: UInt64) -> [String: Any] {
                var payload = StatsigSpec.mockUserValues
                payload[InternalStore.evalTimeKey] = timestamp
                payload["has_updates"] = true
                return payload
            }

            func populateWithPayloads(
                _ payloads: [(key: UserCacheKey, payload: [String: Any])]
            ) throws {
                guard let dir = UserPayloadStore.getSDKKeyDirURL(tempDir, sdkKey) else {
                    fail("Failed to create dir URL")
                    return
                }
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true
                )

                for (key, payload) in payloads {
                    let fileURL = dir.appendingPathComponent(key.fullUserHash)
                    let data = UserPayloadStore.encode(payload)
                    try data?.write(to: fileURL)
                }

                let index = UserPayloadIndex(userPayloads: payloads)

                try index.encode()?.write(
                    to: dir.appendingPathComponent(USER_PAYLOAD_INDEX_FILENAME))
            }

            func setUseMultiFileStorage(_ value: Bool) {
                StorageServiceMigrationStatus.migrationStatus = value ? .done : .initial
            }

            beforeSuite {
                let tempDirectoryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("statsig-tests")
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent("statsig-cache", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    fail("Failed to create dir: \(error)")
                }

                tempDir = tempDirectoryURL
                originalURL = UserPayloadStore.defaultRootDirURL
                UserPayloadStore.defaultRootDirURL = tempDir
            }

            afterSuite {
                if let originalURL = originalURL,
                    UserPayloadStore.defaultRootDirURL != originalURL
                {
                    UserPayloadStore.defaultRootDirURL = originalURL
                }
                if let tempDir = tempDir {
                    try? FileManager.default.removeItem(at: tempDir)
                }
            }

            beforeEach {
                defaults = MockDefaults(data: [:])
                StatsigUserDefaults.defaults = defaults
                TestUtils.clearStorage()
            }

            afterEach {
                TestUtils.clearStorage()
            }

            describe("persistence") {

                beforeEach {
                    setUseMultiFileStorage(true)
                }

                afterEach {
                    setUseMultiFileStorage(false)
                }

                it("writes a payload to a user-scoped file") {
                    let user = StatsigUser(userID: "user_a")
                    let store = InternalStore(sdkKey, user, options: options)
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    store.saveValues(
                        StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                    )

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())
                }

                it("reads payloads from files") {
                    let user = StatsigUser(userID: "user_a")
                    let key = UserCacheKey.from(options, user, sdkKey)

                    try populateWithPayloads([(key, StatsigSpec.mockUserValues)])

                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey)).to(
                        beNil())

                    let store = InternalStore(sdkKey, user, options: options)

                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey)).to(
                        beNil())
                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())
                }

                it("reads the correct payload after updating to a different user") {

                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")

                    let store = InternalStore(sdkKey, userA, options: options)
                    let keyA = UserCacheKey.from(options, userA, sdkKey)
                    let keyB = UserCacheKey.from(options, userB, sdkKey)

                    store.saveValues(StatsigSpec.mockUserValues, keyA, userA.getFullUserHash())

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())

                    store.updateUser(userB)

                    store.saveValues(
                        StatsigSpec.mockUpdatedUserValues, keyB, userB.getFullUserHash()
                    )

                    expect(store.checkGate(forName: "gate_name_2").value).to(beFalse())
                    expect(store.checkGate(forName: "new_gate_name_1").value).to(beTrue())

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keyA)!))
                        .toEventuallyNot(beNil())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keyB)!))
                        .toEventuallyNot(beNil())

                    StorageService.clearCachedServices()

                    let reloadedA = InternalStore(sdkKey, userA, options: options)
                    let reloadedB = InternalStore(sdkKey, userB, options: options)

                    expect(reloadedA.checkGate(forName: "gate_name_2").value).to(beTrue())
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

                    store.saveValues(StatsigSpec.mockUserValues, initialKey, user.getFullUserHash())

                    expect(store.cache.source).toEventually(equal(.Network))
                    expect(
                        store.storageService.userPayload.mappedFullUserHash(v2Key: updatedKey.v2)
                    ).toEventuallyNot(beNil())

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())

                    store.updateUser(updatedUser)
                    expect(store.cache.source).toEventually(equal(.Cache))

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())
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

                    store.saveValues(
                        StatsigSpec.mockUserValues, initialKey, user.getFullUserHash()
                    )

                    expect(store.cache.source).toEventually(equal(.Network))

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())

                    store.updateUser(updatedUser)

                    expect(store.cache.source).toEventually(equal(.Loading))

                    expect(store.checkGate(forName: "gate_name_2").value).to(beFalse())
                }

                it("is resilient to a missing user file") {
                    let user = StatsigUser(userID: "user_a")
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    // Ensure the file doesn't exist
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!)).to(beNil())

                    let store = InternalStore(sdkKey, user, options: options)

                    expect(store.checkGate(forName: "gate_name_2").value).to(beFalse())
                }

                it("is resilient to a corrupted user file") {
                    let user = StatsigUser(userID: "user_a")
                    let store = InternalStore(sdkKey, user, options: options)
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    store.saveValues(
                        StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash()
                    )

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())

                    guard let dir = store.storageService.userPayload.directoryURL else {
                        fail("Failed to get the directory URL")
                        return
                    }
                    try FileManager.default.createDirectory(
                        at: dir,
                        withIntermediateDirectories: true
                    )
                    let fileURL = dir.appendingPathComponent(cacheKey.fullUserHash)
                    let garbage = "not-json".data(using: .utf8)!
                    try garbage.write(to: fileURL)

                    StorageService.clearCachedServices()

                    let reloaded = InternalStore(sdkKey, user, options: options)
                    expect(reloaded.checkGate(forName: "gate_name_2").value).to(beFalse())
                }
            }

            describe("eviction") {

                beforeEach {
                    setUseMultiFileStorage(true)
                }

                afterEach {
                    setUseMultiFileStorage(false)
                }

                it("deletes older user payloads once they reach a threshold") {
                    let payloadStore = UserPayloadStore.forSDKKey(sdkKey)
                    let users = (0..<12).map { StatsigUser(userID: "user_\($0)") }
                    let keys = users.map { UserCacheKey.from(options, $0, sdkKey) }

                    for (index, key) in keys.enumerated() {
                        payloadStore.write(
                            key: key,
                            payload: makePayload(withTimestamp: UInt64(1000 + index))
                        )
                    }

                    let payloadDir = tempDir?
                        .appendingPathComponent(sdkKey)
                        .appendingPathComponent("user-payload")
                    expect(
                        {
                            let files =
                                (try? FileManager.default.contentsOfDirectory(
                                    atPath: payloadDir?.path ?? ""
                                )) ?? []
                            return files.filter { $0 != "_index.json" }.count
                        }()
                    ).toEventually(equal(MAX_CACHED_USER_PAYLOADS_PER_KEY))

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keys[0])!))
                        .toEventually(beNil())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keys[1])!))
                        .toEventually(beNil())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keys[7])!))
                        .toEventuallyNot(beNil())
                }

                it("persists the index entries after eviction") {
                    let payloadStore = UserPayloadStore.forSDKKey(sdkKey)
                    let users = (0..<11).map { StatsigUser(userID: "index_user_\($0)") }
                    let keys = users.map { UserCacheKey.from(options, $0, sdkKey) }

                    for (index, key) in keys.enumerated() {
                        payloadStore.write(
                            key: key,
                            payload: makePayload(withTimestamp: UInt64(2000 + index))
                        )
                    }

                    expect(
                        {
                            guard
                                let data = try? Data(contentsOf: getIndexFileURL(sdkKey)!),
                                let index = UserPayloadIndex.decode(data)
                            else {
                                return -1
                            }
                            return index.entries.count
                        }()
                    ).toEventually(equal(5))
                }
            }

            describe("migration") {

                beforeEach {
                    StorageServiceMigrationStatus.migrationStatus = .initial
                }

                afterEach {
                    StorageServiceMigrationStatus.migrationStatus = .initial
                }

                it("does not fall back to userDefaults when index file exists") {
                    let user = StatsigUser(userID: "user_a")
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    try populateWithPayloads([(cacheKey, StatsigSpec.mockUserValues)])

                    defaults.setDictionarySafe(
                        [cacheKey.fullUserWithSDKKey: StatsigSpec.mockUpdatedUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, user, options: options)

                    expect(StorageServiceMigrationStatus.migrationStatus).toEventually(equal(.done))

                    expect(store.checkGate(forName: "gate_name_2").value).to(beTrue())
                    expect(store.checkGate(forName: "new_gate_name_1").value).to(beFalse())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .toEventuallyNot(beNil(), description: "Defaults Check")
                }

                it("migrates existing UserDefaults payloads into user-scoped files") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let otherSdkKey = "client-other-key"

                    let keyA = UserCacheKey.from(options, userA, sdkKey)
                    let keyB = UserCacheKey.from(options, userB, otherSdkKey)

                    defaults.setDictionarySafe(
                        [
                            keyA.fullUserWithSDKKey: StatsigSpec.mockUserValues,
                            keyB.fullUserWithSDKKey: StatsigSpec.mockUpdatedUserValues,
                        ],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, userA, options: options)
                    StorageServiceMigrationStatus.setNeedsMigration()
                    store.migrateIfNeeded()
                    expect(StorageServiceMigrationStatus.migrationStatus).toEventually(equal(.done))

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, keyA)!))
                        .toNot(beNil(), description: "key A")
                    expect(try? Data(contentsOf: userPayloadFileURL(otherSdkKey, keyB)!))
                        .toNot(beNil(), description: "key B")
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .to(beNil())
                }

                it("migrates v2 keys from UserDefaults payloads and reads them") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let cacheKeyB = UserCacheKey.from(options, userB, sdkKey)

                    defaults.setDictionarySafe(
                        [cacheKeyB.v2: StatsigSpec.mockUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, userA, options: options)
                    StorageServiceMigrationStatus.setNeedsMigration()
                    store.migrateIfNeeded()
                    expect(StorageServiceMigrationStatus.migrationStatus).toEventually(equal(.done))

                    expect(legacyPayload(cacheKeyB.v2)).toNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .to(beNil())
                }

                it("migrates v1 keys from UserDefaults payloads and reads them") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let cacheKeyB = UserCacheKey.from(options, userB, sdkKey)

                    defaults.setDictionarySafe(
                        [cacheKeyB.v1: StatsigSpec.mockUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, userA, options: options)
                    StorageServiceMigrationStatus.setNeedsMigration()
                    store.migrateIfNeeded()
                    expect(StorageServiceMigrationStatus.migrationStatus).toEventually(equal(.done))

                    expect(legacyPayload(cacheKeyB.v1)).toNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .to(beNil())
                }
            }

            describe("sdk config") {

                beforeEach {
                    StorageServiceMigrationStatus.migrationStatus = .initial
                }

                afterEach {
                    StorageServiceMigrationStatus.migrationStatus = .initial
                }

                it("processes sdk configs and persists storage toggle for next launch") {
                    let user = StatsigUser(userID: "user_a")
                    let store = InternalStore(sdkKey, user, options: options)
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    var payload = StatsigSpec.mockUserValues
                    let multiFileStoreGate = "multi_file_store_gate"
                    payload[InternalStore.gatesKey] = [
                        multiFileStoreGate: ["value": true, "rule_id": "rule_id_multi_file"]
                    ]
                    payload[InternalStore.sdkConfigsKey] = ["store_g": multiFileStoreGate]
                    payload[InternalStore.hashUsedKey] = "none"

                    setUseMultiFileStorage(false)

                    store.saveValues(payload, cacheKey, user.getFullUserHash())

                    expect(StorageServiceMigrationStatus.migrationStatus).toEventually(
                        equal(.pending))

                    store.migrateIfNeeded()

                    expect(StorageService.useMultiFileStorage).toEventually(beTrue())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())
                    expect(try? Data(contentsOf: getIndexFileURL(sdkKey)!))
                        .toEventuallyNot(beNil())
                }

                it("uses the new storage in the current session") {
                    let userA = StatsigUser(userID: "user_a")
                    let userB = StatsigUser(userID: "user_b")
                    let store = InternalStore(sdkKey, userA, options: options)
                    let cacheKeyA = UserCacheKey.from(options, userA, sdkKey)
                    let cacheKeyB = UserCacheKey.from(options, userB, sdkKey)

                    var payload = StatsigSpec.mockUserValues
                    let multiFileStoreGate = "multi_file_store_gate"
                    payload[InternalStore.gatesKey] = [
                        multiFileStoreGate: ["value": true, "rule_id": "rule_id_multi_file"]
                    ]
                    payload[InternalStore.sdkConfigsKey] = ["store_g": multiFileStoreGate]
                    payload[InternalStore.hashUsedKey] = "none"

                    setUseMultiFileStorage(false)

                    store.saveValues(payload, cacheKeyA, userA.getFullUserHash())

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .to(equal(.pending))
                    expect(StorageService.useMultiFileStorage).to(beTrue())

                    // NOTE: This doesn't have the SDK config. It's fine as long as we're not disabling storage.
                    store.saveValues(
                        StatsigSpec.mockUpdatedUserValues, cacheKeyB, userB.getFullUserHash())

                    store.migrateIfNeeded()

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKeyA)!))
                        .toEventuallyNot(beNil())
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKeyB)!))
                        .toEventuallyNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .to(beNil())
                }

            }

            describe("concurrency") {
                pending(
                    "avoids race conditions if a caller tries to read a payload before the migration completes"
                ) {
                }
                pending(
                    "hot-swaps from UserDefaults to file storage only after migration completes"
                ) {
                    // Intended race to cover:
                    // 1. Seed UserDefaults with payloads and start migration from Store A.
                    // 2. Before migration finishes writing files/index, create Store B.
                    // 3. Assert Store B still reads the UserDefaults payload (old world).
                    // 4. After migration completion, assert Store B switches to file storage and
                    //    no longer falls back to UserDefaults.
                    //
                    // This test needs deterministic control over async migration write timing.
                }
            }

        }
    }
}
