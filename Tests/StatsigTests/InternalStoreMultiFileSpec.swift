import Foundation
import Nimble
import OHHTTPStubs
import Quick

@testable import Statsig

#if !COCOAPODS
import OHHTTPStubsSwift
#endif

final class InternalStoreMultiFileSpec: BaseSpec {
    private final class InMemoryStorageProvider: NSObject, StorageProvider {
        private let lock = NSLock()
        private var dataByKey: [String: Data] = [:]
        private(set) var didReadIndexFile = false

        private(set) var readKeys: [String] = []
        private(set) var writeKeys: [String] = []
        private(set) var removeKeys: [String] = []

        func read(_ key: String) -> Data? {
            return lock.withLock {
                if key.hasSuffix(USER_PAYLOAD_INDEX_FILENAME) {
                    didReadIndexFile = true
                }
                readKeys.append(key)
                return dataByKey[key]
            }
        }

        func write(_ value: Data, _ key: String) {
            lock.withLock {
                writeKeys.append(key)
                dataByKey[key] = value
            }
        }

        func remove(_ key: String) {
            lock.withLock {
                removeKeys.append(key)
                dataByKey.removeValue(forKey: key)
            }
        }

        func data(for key: String) -> Data? {
            return lock.withLock { dataByKey[key] }
        }
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

            var tempDir: URL?
            var originalURL = FileStorageAdapter.defaultRootDirectory

            // TODO: Replace some of the helper functions below with static utils in UserPayloadStore

            let legacyPayloadDirectory: () -> URL? = {
                tempDir?
                    .appendingPathComponent("_legacy", isDirectory: true)
                    .appendingPathComponent(USER_PAYLOAD_DIRNAME, isDirectory: true)
            }

            func url(for key: [String], isDirectory: Bool) -> URL? {
                guard let rootDirectory = tempDir, !key.isEmpty else {
                    return nil
                }

                let lastIndex = key.index(before: key.endIndex)
                return key.indices.reduce(rootDirectory) { partial, index in
                    partial.appendingPathComponent(
                        key[index],
                        isDirectory: index == lastIndex ? isDirectory : true
                    )
                }
            }

            func sdkPayloadDirectory(_ sdkKey: String) -> URL? {
                return url(for: UserPayloadStore.sdkDirectoryKey(sdkKey: sdkKey), isDirectory: true)
            }

            func userPayloadFileURL(_ sdkKey: String, _ cacheKey: UserCacheKey) -> URL? {
                return sdkPayloadDirectory(sdkKey)?
                    .appendingPathComponent(cacheKey.fullUserHash, isDirectory: false)
            }

            func getIndexFileURL(_ sdkKey: String) -> URL? {
                return sdkPayloadDirectory(sdkKey)?
                    .appendingPathComponent(USER_PAYLOAD_INDEX_FILENAME, isDirectory: false)
            }

            func readJSONPayload(_ url: URL?) -> [String: Any]? {
                guard
                    let fileURL = url,
                    let data = try? Data(contentsOf: fileURL)
                else {
                    return nil
                }

                return UserPayloadStore.decode(data)
            }

            func legacyPayload(_ key: String) -> [String: Any]? {
                return readJSONPayload(
                    legacyPayloadDirectory()?.appendingPathComponent(key, isDirectory: false))
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
                guard let dir = sdkPayloadDirectory(sdkKey) else {
                    fail("Failed to create dir URL")
                    return
                }
                try FileManager.default.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true
                )

                for (key, payload) in payloads {
                    let fileURL = dir.appendingPathComponent(key.fullUserHash, isDirectory: false)
                    let data = UserPayloadStore.encode(payload)
                    try data?.write(to: fileURL)
                }

                let index = UserPayloadIndex(userPayloads: payloads)

                try index.encode()?.write(
                    to: dir.appendingPathComponent(USER_PAYLOAD_INDEX_FILENAME, isDirectory: false))
            }

            func setUseMultiFileStorage(_ value: Bool) {
                if value {
                    StorageServiceMigrationStatus.resetState(
                        migrationStatus: .multiFile,
                        hasStateBeenSet: true
                    )
                } else {
                    StorageServiceMigrationStatus.resetState()
                }
            }

            beforeSuite {
                let tempDirectoryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("statsig-tests", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent("statsig-cache", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(
                        at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    fail("Failed to create dir: \(error)")
                }

                tempDir = tempDirectoryURL
                originalURL = FileStorageAdapter.defaultRootDirectory
                FileStorageAdapter.defaultRootDirectory = tempDir
            }

            afterSuite {
                if let originalURL = originalURL,
                    FileStorageAdapter.defaultRootDirectory != originalURL
                {
                    FileStorageAdapter.defaultRootDirectory = originalURL
                }
                if let tempDir = tempDir {
                    try? FileManager.default.removeItem(at: tempDir)
                }
            }

            beforeEach {
                defaults = MockDefaults(data: [:])
                StatsigUserDefaults.defaults = defaults
                TestUtils.clearStorage(rootDir: tempDir)
            }

            afterEach {
                TestUtils.clearStorage(rootDir: tempDir)
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

                    StorageService.clearCachedInstances()

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
                        store.storageService?.userPayload.mappedFullUserHash(v2Key: updatedKey.v2)
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

                    guard let dir = sdkPayloadDirectory(sdkKey) else {
                        fail("Failed to get the directory URL")
                        return
                    }
                    try FileManager.default.createDirectory(
                        at: dir,
                        withIntermediateDirectories: true
                    )
                    let fileURL = dir.appendingPathComponent(
                        cacheKey.fullUserHash,
                        isDirectory: false
                    )
                    let garbage = "not-json".data(using: .utf8)!
                    try garbage.write(to: fileURL)

                    StorageService.clearCachedInstances()

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
                    let payloadStore = UserPayloadStore.forSDKKey(
                        sdkKey,
                        storageAdapter: FileStorageAdapter(rootDirectory: tempDir)
                    )
                    let users = (0..<12).map { StatsigUser(userID: "user_\($0)") }
                    let keys = users.map { UserCacheKey.from(options, $0, sdkKey) }

                    for (index, key) in keys.enumerated() {
                        payloadStore.write(
                            key: key,
                            payload: makePayload(withTimestamp: UInt64(1000 + index))
                        )
                    }

                    let payloadDir = sdkPayloadDirectory(sdkKey)
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
                    let payloadStore = UserPayloadStore.forSDKKey(
                        sdkKey,
                        storageAdapter: FileStorageAdapter(rootDirectory: tempDir)
                    )
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

            describe("storage adapter bridge") {
                beforeEach {
                    setUseMultiFileStorage(true)
                }

                afterEach {
                    setUseMultiFileStorage(false)
                }

                it("maps adapter keys to dot-delimited storage provider keys") {
                    let provider = InMemoryStorageProvider()
                    let adapter = StorageProviderToAdapter(storageProvider: provider)
                    let key = ["client-sdk", "user-payload", "abc"]
                    let value = "hello".data(using: .utf8)!

                    adapter.write(value, key, options: [])

                    switch adapter.read(key) {
                    case .data(let readValue):
                        expect(readValue).to(equal(value))
                    default:
                        fail("Expected read to return persisted data")
                    }

                    adapter.remove(key)

                    expect(provider.writeKeys).to(contain("client-sdk.user-payload.abc"))
                    expect(provider.readKeys).to(contain("client-sdk.user-payload.abc"))
                    expect(provider.removeKeys).to(contain("client-sdk.user-payload.abc"))
                }

                it("returns notFound when the provider does not contain data for a key") {
                    let provider = InMemoryStorageProvider()
                    let adapter = StorageProviderToAdapter(storageProvider: provider)

                    switch adapter.read(["missing", "key"]) {
                    case .notFound:
                        break
                    default:
                        fail("Expected notFound for missing provider keys")
                    }
                }

                it("uses StorageProvider-backed adapter for multi-file user payload persistence") {
                    let provider = InMemoryStorageProvider()
                    let optionsWithProvider = StatsigOptions(storageProvider: provider)
                    let user = StatsigUser(userID: "provider_user")
                    let cacheKey = UserCacheKey.from(optionsWithProvider, user, sdkKey)
                    let store = InternalStore(sdkKey, user, options: optionsWithProvider)

                    store.saveValues(
                        StatsigSpec.mockUserValues,
                        cacheKey,
                        user.getFullUserHash()
                    )

                    let payloadStorageKey =
                        "\(sdkKey).\(USER_PAYLOAD_DIRNAME).\(cacheKey.fullUserHash)"
                    let indexStorageKey =
                        "\(sdkKey).\(USER_PAYLOAD_DIRNAME).\(USER_PAYLOAD_INDEX_FILENAME)"

                    expect(provider.data(for: payloadStorageKey)).toEventuallyNot(beNil())
                    expect(provider.data(for: indexStorageKey)).toEventuallyNot(beNil())

                    StorageService.clearCachedInstances()
                    StorageServiceMigrationStatus.resetState(persist: false)

                    let reloadedStore = InternalStore(sdkKey, user, options: optionsWithProvider)
                    expect(reloadedStore.checkGate(forName: "gate_name_2").value).to(beTrue())
                }

                it("reads index on initialization") {
                    let provider = InMemoryStorageProvider()
                    let optionsWithProvider = StatsigOptions(storageProvider: provider)
                    let indexedUser = StatsigUser(userID: "index_lookup_user")

                    let _ = InternalStore(sdkKey, indexedUser, options: optionsWithProvider)
                    expect(provider.didReadIndexFile).to(beTrue())
                }
            }

            describe("migration") {

                beforeEach {
                    StorageServiceMigrationStatus.resetState()
                }

                afterEach {
                    StorageServiceMigrationStatus.resetState()
                }

                it("does not fall back to userDefaults when the UserDefaults flag is set") {
                    defaults.setValue(
                        "multi-file",
                        forKey: UserDefaultsKeys.storageMigrationStatusKey
                    )

                    let user = StatsigUser(userID: "user_a")
                    let cacheKey = UserCacheKey.from(options, user, sdkKey)

                    try populateWithPayloads([(cacheKey, StatsigSpec.mockUserValues)])

                    defaults.setDictionarySafe(
                        [cacheKey.fullUserWithSDKKey: StatsigSpec.mockUpdatedUserValues],
                        forKey: UserDefaultsKeys.localStorageKey
                    )

                    let store = InternalStore(sdkKey, user, options: options)

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.multiFile))

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
                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.multiFile))

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
                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.multiFile))

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
                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.multiFile))

                    expect(legacyPayload(cacheKeyB.v1)).toNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .to(beNil())
                }
            }

            describe("sdk config") {

                beforeEach {
                    StorageServiceMigrationStatus.resetState()
                }

                afterEach {
                    Statsig.client?.shutdown()
                    Statsig.client = nil
                    HTTPStubs.removeAllStubs()
                    TestUtils.resetDefaultURLs()
                    StorageServiceMigrationStatus.resetState()
                }

                it("processes sdk configs and persists storage toggle") {
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

                    store.saveValues(payload, cacheKey, user.getFullUserHash())

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.migrating(started: false)))
                    expect(defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey))
                        .toEventually(equal("migrating"))

                    store.migrateIfNeeded()

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventuallyNot(equal(.legacy))
                    expect(defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey))
                        .toEventually(equal("multi-file"))
                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())
                    expect(try? Data(contentsOf: getIndexFileURL(sdkKey)!))
                        .toEventuallyNot(beNil())
                }

                let possibleStatuses: [StorageServiceMigrationStatus] = [
                    .legacy,
                    .migrating(started: false),
                    .migrating(started: true),
                    .multiFile,
                ]

                possibleStatuses.forEach { initialStatus in
                    it(
                        "does not process sdk configs when has_updates is false and status is \(initialStatus)"
                    ) {
                        StorageServiceMigrationStatus.resetState(migrationStatus: initialStatus)
                        let user = StatsigUser(userID: "user_a")
                        let store = InternalStore(sdkKey, user, options: options)
                        let cacheKey = UserCacheKey.from(options, user, sdkKey)

                        let payload = ["has_updates": false]

                        waitUntil { done in
                            store.saveValues(payload, cacheKey, user.getFullUserHash(), done)
                        }

                        expect(StorageServiceMigrationStatus.migrationStatus)
                            .to(equal(initialStatus))

                        switch initialStatus {
                        case .legacy:
                            expect(
                                defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey)
                            )
                            .toEventually(beNil())
                        case .migrating:
                            expect(
                                defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey)
                            )
                            .toEventually(equal("migrating"))
                        case .multiFile:
                            expect(
                                defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey)
                            )
                            .toEventually(equal("multi-file"))
                        }

                    }
                }

                it("does not process sdk configs when has_updates is missing") {
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
                    payload.removeValue(forKey: "has_updates")

                    store.saveValues(payload, cacheKey, user.getFullUserHash())

                    expect(StorageServiceMigrationStatus.migrationStatus).toEventually(
                        equal(.legacy))
                    expect(defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey))
                        .toEventually(beNil())
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

                    store.saveValues(payload, cacheKeyA, userA.getFullUserHash())

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .to(equal(.migrating(started: false)))
                    expect(defaults.string(forKey: UserDefaultsKeys.storageMigrationStatusKey))
                        .to(equal("migrating"))

                    // Save a payload that would disable multi-file storage, but it doesn't because it's been set this session
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

                it(
                    "does not enable multi-file storage from sdk configs when EXPERIMENTAL_storageType is legacy"
                ) {
                    let user = StatsigUser(userID: "user_a")
                    let legacyOptions = StatsigOptions(EXPERIMENTAL_storageType: .legacy)
                    StorageServiceMigrationStatus.applyStorageTypeOption(
                        legacyOptions.EXPERIMENTAL_storageType)
                    let store = InternalStore(sdkKey, user, options: legacyOptions)
                    let cacheKey = UserCacheKey.from(legacyOptions, user, sdkKey)

                    var payload = StatsigSpec.mockUserValues
                    let multiFileStoreGate = "multi_file_store_gate"
                    payload[InternalStore.gatesKey] = [
                        multiFileStoreGate: ["value": true, "rule_id": "rule_id_multi_file"]
                    ]
                    payload[InternalStore.sdkConfigsKey] = ["store_g": multiFileStoreGate]
                    payload[InternalStore.hashUsedKey] = "none"

                    store.saveValues(payload, cacheKey, user.getFullUserHash())

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.legacy))
                }

                it("forces multi-file storage when EXPERIMENTAL_storageType is multiFile") {
                    let user = StatsigUser(userID: "user_a")
                    let multiFileOptions = StatsigOptions(EXPERIMENTAL_storageType: .multiFile)
                    StorageServiceMigrationStatus.applyStorageTypeOption(
                        multiFileOptions.EXPERIMENTAL_storageType)
                    let store = InternalStore(sdkKey, user, options: multiFileOptions)
                    let cacheKey = UserCacheKey.from(multiFileOptions, user, sdkKey)

                    expect(StorageServiceMigrationStatus.migrationStatus)
                        .toEventually(equal(.migrating(started: false)))

                    store.saveValues(StatsigSpec.mockUserValues, cacheKey, user.getFullUserHash())

                    expect(try? Data(contentsOf: userPayloadFileURL(sdkKey, cacheKey)!))
                        .toEventuallyNot(beNil())
                    expect(defaults.dictionary(forKey: UserDefaultsKeys.localStorageKey))
                        .to(beNil())
                }

                it(
                    "logs the storage gate exposure during initialize when EXPERIMENTAL_storageType is auto"
                ) {
                    let eventHost = "InternalStoreMultiFileSpec"
                    let multiFileStoreGate = "multi_file_store_gate"
                    var logs: [[String: Any]] = []

                    NetworkService.defaultEventLoggingURL = URL(
                        string: "http://\(eventHost)/v1/rgstr")
                    TestUtils.captureLogs(host: eventHost) { captured in
                        if let events = captured["events"] as? [[String: Any]] {
                            logs.append(
                                contentsOf: events.filter {
                                    $0["eventName"] as? String == "statsig::gate_exposure"
                                })
                        }
                    }

                    var payload = StatsigSpec.mockUserValues
                    payload[InternalStore.gatesKey] = [
                        multiFileStoreGate: ["value": true, "rule_id": "rule_id_multi_file"]
                    ]
                    payload[InternalStore.sdkConfigsKey] = ["store_g": multiFileStoreGate]
                    payload[InternalStore.hashUsedKey] = "none"

                    let autoOptions = StatsigOptions(
                        EXPERIMENTAL_storageType: .auto,
                        disableDiagnostics: true
                    )
                    _ = TestUtils.startWithResponseAndWait(payload, options: autoOptions)

                    waitUntil { done in
                        Statsig.flush(completion: done)
                    }

                    expect(
                        logs.contains {
                            $0[jsonDict: "metadata"]?["gate"] as? String == multiFileStoreGate
                        }
                    ).to(beTrue())
                }

                it(
                    "does not log the storage gate exposure during initialize when EXPERIMENTAL_storageType is legacy"
                ) {
                    let eventHost = "InternalStoreMultiFileSpec"
                    let multiFileStoreGate = "multi_file_store_gate"
                    var logs: [[String: Any]] = []

                    NetworkService.defaultEventLoggingURL = URL(
                        string: "http://\(eventHost)/v1/rgstr")
                    TestUtils.captureLogs(host: eventHost) { captured in
                        if let events = captured["events"] as? [[String: Any]] {
                            logs.append(
                                contentsOf: events.filter {
                                    $0["eventName"] as? String == "statsig::gate_exposure"
                                })
                        }
                    }

                    var payload = StatsigSpec.mockUserValues
                    payload[InternalStore.gatesKey] = [
                        multiFileStoreGate: ["value": true, "rule_id": "rule_id_multi_file"]
                    ]
                    payload[InternalStore.sdkConfigsKey] = ["store_g": multiFileStoreGate]
                    payload[InternalStore.hashUsedKey] = "none"

                    let legacyOptions = StatsigOptions(
                        EXPERIMENTAL_storageType: .legacy,
                        disableDiagnostics: true
                    )
                    _ = TestUtils.startWithResponseAndWait(payload, options: legacyOptions)

                    waitUntil { done in
                        Statsig.flush(completion: done)
                    }

                    expect(
                        logs.contains {
                            $0[jsonDict: "metadata"]?["gate"] as? String == multiFileStoreGate
                        }
                    ).to(beFalse())
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
