import Foundation

// TODO: Audit thread-safety across index state and background persistence.

internal let USER_PAYLOAD_DIRNAME = "user-payload"
internal let USER_PAYLOAD_INDEX_FILENAME = "_index.json"
internal let LEGACY_DIRECTORY_KEY = ["_legacy", USER_PAYLOAD_DIRNAME]

final class UserPayloadStore {

    // MARK: Static

    private static let storesLock = NSLock()
    private static var storesBySDKKey: [String: UserPayloadStore] = [:]

    static func forSDKKey(
        _ sdkKey: String,
        storageAdapter: StorageAdapter
    )
        -> UserPayloadStore
    {
        storesLock.withLock {
            if let existing = storesBySDKKey[sdkKey] {
                return existing
            }
            let created = UserPayloadStore(
                sdkKey: sdkKey,
                storageAdapter: storageAdapter
            )
            storesBySDKKey[sdkKey] = created
            return created
        }
    }

    // MARK: Params & Init

    let sdkKey: String
    let storageAdapter: StorageAdapter

    private let evictionQueue: DispatchQueue
    private let indexStore: UserPayloadIndexStore
    private let directoryKey: [String]
    @LockedValue
    private var payloadCacheByFilename: [String: [String: Any]] = [:]

    private init(sdkKey: String, storageAdapter: StorageAdapter) {
        self.sdkKey = sdkKey
        self.storageAdapter = storageAdapter
        self.directoryKey = Self.sdkDirectoryKey(sdkKey: sdkKey)
        let sdkKeyPrefix = String(sdkKey.dropFirst(7).prefix(4))
        self.evictionQueue = DispatchQueue(
            label: "com.statsig.userPayload.eviction.\(sdkKeyPrefix)",
            qos: .utility)
        self.indexStore = UserPayloadIndexStore(
            sdkKey: sdkKey,
            storageAdapter: storageAdapter
        )
    }

    // MARK: Utils

    private func filename(for key: UserCacheKey) -> String {
        return key.fullUserHash
    }

    internal static func sdkDirectoryKey(sdkKey: String) -> [String] {
        return [sdkKey, USER_PAYLOAD_DIRNAME]
    }

    private func userPayloadKey(_ userCacheKey: UserCacheKey) -> [String] {
        return self.directoryKey + [filename(for: userCacheKey)]
    }

    private static func legacyPayloadKey(_ filename: String) -> [String] {
        return LEGACY_DIRECTORY_KEY + [filename]
    }

    // MARK: Write

    func write(key: UserCacheKey, payload: [String: Any]) {
        guard
            let data = UserPayloadStore.encode(payload)
        else {
            // TODO: Handle errors
            return
        }
        let payloadTimestamp = UserPayloadIndexStore.payloadTimestamp(payload)
        payloadCacheByFilename[filename(for: key)] = payload

        write(key: key, payloadData: data, payloadTimestamp: payloadTimestamp)
    }

    func write(key: UserCacheKey, payloadData data: Data, payloadTimestamp: UInt64?) {
        let payloadKey = userPayloadKey(key)
        let storageAdapter = self.storageAdapter

        // Update index
        let payloadCount = indexStore.updateIndexForWrite(
            key: key,
            payloadTimestamp: payloadTimestamp
        )

        // Persist payload
        StorageService.persistenceQueue.async(flags: .barrier) {
            storageAdapter.write(data, payloadKey, options: .createFolderIfNeeded)
        }

        // Persist index
        if payloadCount <= MAX_CACHED_USER_PAYLOADS_PER_KEY {
            indexStore.persistIndexIfAllowed()
        } else {
            scheduleEviction()
        }
    }

    // Used for migrations
    private static func writeForMigration(
        key: [String],
        payload: [String: Any],
        storageAdapter: StorageAdapter
    ) {
        guard let data = encode(payload) else {
            // TODO: Handle errors
            return
        }

        StorageService.persistenceQueue.async(flags: .barrier) {
            storageAdapter.write(data, key, options: [.withoutOverwriting])
        }
    }

    // MARK: Read

    func read(
        key: UserCacheKey,
        legacyMemoryCache: [String: [String: Any]]? = nil
    ) -> [String: Any]? {
        guard let payload = readPayload(key: key, legacyMemoryCache: legacyMemoryCache) else {
            indexStore.removeMissingPayload(fullUserHash: key.fullUserHash)
            return nil
        }

        let shouldScheduleEviction = indexStore.updateIndexForRead(
            key: key,
            payload: payload,
            maxCachedPayloads: MAX_CACHED_USER_PAYLOADS_PER_KEY
        )
        if shouldScheduleEviction {
            scheduleEviction()
        }
        return payload
    }

    private func readPayload(
        key: UserCacheKey,
        legacyMemoryCache: [String: [String: Any]]?
    ) -> [String: Any]? {
        let filename = filename(for: key)
        if let payload = payloadCacheByFilename[filename] {
            return payload
        }

        guard
            let payload = readPayloadFromStorage(key: key, legacyMemoryCache: legacyMemoryCache)
        else {
            return nil
        }

        setCachedPayloadIfEmpty(payload, forFilename: filename)

        return payload
    }

    private func readPayloadFromStorage(
        key: UserCacheKey,
        legacyMemoryCache: [String: [String: Any]]?
    ) -> [String: Any]? {
        if let payload = UserPayloadStore.read(
            key: userPayloadKey(key),
            storageAdapter: storageAdapter)
        {
            return payload
        }

        if let payload = readUsingMappedKey(key: key, legacyMemoryCache: legacyMemoryCache) {
            return payload
        }

        if let payload = readLegacy(key.v2) {
            return payload
        }

        if let payload = readLegacy(key.v1) {
            return payload
        }

        return nil
    }

    private func readUsingMappedKey(
        key: UserCacheKey,
        legacyMemoryCache: [String: [String: Any]]?
    ) -> [String: Any]? {
        guard let mappedKey = indexStore.mappedFullUserHash(v2Key: key.v2) else {
            return nil
        }

        if let mappedCachedValues = legacyMemoryCache?["\(mappedKey):\(sdkKey)"] {
            return mappedCachedValues
        }

        if let payload = payloadCacheByFilename[mappedKey] {
            return payload
        }

        let payloadKey = self.directoryKey + [mappedKey]
        if let payload = Self.read(key: payloadKey, storageAdapter: storageAdapter) {
            setCachedPayloadIfEmpty(payload, forFilename: mappedKey)
            return payload
        }

        // cacheKeyMapping has a key, but that key doesn't exist in storage. Since
        // writes are async, a mapped payload can temporarily miss before the file
        // is flushed. This function keeps the mapping and lets
        // eviction/reconciliation clean up truly stale entries.
        return nil
    }

    static func read(key: [String], storageAdapter: StorageAdapter) -> [String: Any]? {
        guard !key.isEmpty else {
            // TODO: Handle errors
            return nil
        }

        let data: Data
        let readResult = StorageService.persistenceQueue.sync {
            storageAdapter.read(key)
        }
        switch readResult {
        case .data(let readData):
            data = readData
        case .notFound, .error:
            // TODO: Handle adapter read errors
            return nil
        }

        // TODO: Handle errors
        return decode(data)
    }

    // MARK: Delete

    func remove(key: UserCacheKey) {
        let payloadKey = userPayloadKey(key)
        guard !payloadKey.isEmpty else {
            // TODO: Handle errors
            return
        }
        let storageAdapter = self.storageAdapter
        payloadCacheByFilename.removeValue(forKey: filename(for: key))

        // TODO: Handle errors
        StorageService.persistenceQueue.async(flags: .barrier) {
            storageAdapter.remove(payloadKey)
        }
    }

    // MARK: Encoding

    internal static func encode(_ value: [String: Any]) -> Data? {
        // TODO: Handle errors
        return try? JSONSerialization.data(withJSONObject: value, options: [])
    }

    internal static func decode(_ data: Data) -> [String: Any]? {
        // TODO: Handle errors
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }

    // MARK: Migration and Compatibility

    // NOTE: Only call this function from InternalStore.migrateIfNeeded
    static func migrateIfNeeded(
        _ cacheByID: [String: [String: Any]],
        _ cacheKeyMapping: [String: String],
        _ defaults: DefaultsLike,
        _ storageAdapter: StorageAdapter
    ) {
        var parsedEntriesBySDK: [String: [(fullUserHash: String, payload: [String: Any])]] = [:]
        var legacyEntries: [(fullUserHash: String, payload: [String: Any])] = []
        for (key, payload) in cacheByID {
            if let parsed = extractSDKKey(from: key) {
                parsedEntriesBySDK[parsed.sdkKey, default: []].append(
                    (fullUserHash: parsed.baseKey, payload: payload)
                )
            } else {
                legacyEntries.append((fullUserHash: key, payload: payload))
            }
        }

        var reverseCacheKeyMap: [String: [String: String]] = [:]
        for (v2, full) in cacheKeyMapping {
            if let parsed = extractSDKKey(from: full) {
                reverseCacheKeyMap[parsed.sdkKey, default: [:]][parsed.baseKey] = v2
            }
        }

        for (sdkKey, entries) in parsedEntriesBySDK {
            var index = UserPayloadIndex(entries: [:], cacheKeyMapping: [:])
            let selectedEntries =
                entries
                .sorted { lhs, rhs in
                    Time.parse(lhs.payload[InternalStore.evalTimeKey])
                        > Time.parse(rhs.payload[InternalStore.evalTimeKey])
                }
                .prefix(MAX_CACHED_USER_PAYLOADS_PER_KEY)
            let sdkDirectoryKey = Self.sdkDirectoryKey(sdkKey: sdkKey)
            StorageService.persistenceQueue.async(flags: .barrier) {
                storageAdapter.createFolderIfNeeded(sdkDirectoryKey)
            }

            for entry in selectedEntries {
                index.entries[entry.fullUserHash] = IndexEntry(
                    timestamp: Time.parse(entry.payload[InternalStore.evalTimeKey]))
                if let v2Key = reverseCacheKeyMap[sdkKey]?[entry.fullUserHash] {
                    index.cacheKeyMapping[v2Key] = entry.fullUserHash
                }

                UserPayloadStore.writeForMigration(
                    key: sdkDirectoryKey + [entry.fullUserHash],
                    payload: entry.payload,
                    storageAdapter: storageAdapter
                )
            }
            UserPayloadIndexStore.writeForMigration(
                key: sdkDirectoryKey + [USER_PAYLOAD_INDEX_FILENAME],
                index: index,
                storageAdapter: storageAdapter
            )
        }

        let selectedLegacyEntries =
            legacyEntries
            .sorted { lhs, rhs in
                Time.parse(lhs.payload[InternalStore.evalTimeKey])
                    > Time.parse(rhs.payload[InternalStore.evalTimeKey])
            }
            .prefix(MAX_CACHED_USER_PAYLOADS_PER_KEY)

        if selectedLegacyEntries.count > 0 {
            StorageService.persistenceQueue.async(flags: .barrier) {
                storageAdapter.createFolderIfNeeded(LEGACY_DIRECTORY_KEY)
            }

            for entry in selectedLegacyEntries {
                Self.writeForMigration(
                    key: Self.legacyPayloadKey(entry.fullUserHash),
                    payload: entry.payload,
                    storageAdapter: storageAdapter
                )
            }
        }

        StorageService.persistenceQueue.async(flags: .barrier) {
            defaults.removeObject(forKey: UserDefaultsKeys.localStorageKey)
            defaults.removeObject(forKey: UserDefaultsKeys.cacheKeyMappingKey)
            StorageServiceMigrationStatus.markMigrationDone()
        }
    }

    func readLegacy(_ filename: String) -> [String: Any]? {
        return Self.read(
            key: Self.legacyPayloadKey(filename),
            storageAdapter: storageAdapter
        )
    }

    func mappedFullUserHash(v2Key: String) -> String? {
        return indexStore.mappedFullUserHash(v2Key: v2Key)
    }

    // MARK: Test utils

    internal static func clearCachedInstances(
        _ rootDir: URL? = FileStorageAdapter.defaultRootDirectory
    ) {
        storesLock.withLock {
            storesBySDKKey.removeAll()
        }
    }

    // MARK: Eviction

    private func runEviction() {
        let evicted = indexStore.evictedFilenames(
            maxCachedPayloads: MAX_CACHED_USER_PAYLOADS_PER_KEY)

        if evicted.isEmpty {
            indexStore.persistIndexIfAllowed()
            return
        }

        $payloadCacheByFilename.withLock { payloadCacheByFilename in
            for filename in evicted {
                payloadCacheByFilename.removeValue(forKey: filename)
            }
        }

        let storageAdapter = self.storageAdapter
        let sdkDirectoryKey = self.directoryKey
        StorageService.persistenceQueue.async(flags: .barrier) {
            for filename in evicted {
                storageAdapter.remove(sdkDirectoryKey + [filename])
            }
        }
        indexStore.persistIndexIfAllowed()
    }

    private func scheduleEviction() {
        evictionQueue.async { [weak self] in
            self?.runEviction()
        }
    }

    func setCachedPayloadIfEmpty(_ payload: [String: Any], forFilename filename: String) {
        $payloadCacheByFilename.withLock { payloadCacheByFilename in
            guard payloadCacheByFilename[filename] == nil else { return }
            payloadCacheByFilename[filename] = payload
        }
    }

}

// MARK: Utils

fileprivate let sdkKeyPrefix = "client-"

fileprivate func extractSDKKey(from cacheKey: String) -> (baseKey: String, sdkKey: String)? {
    guard let separatorIndex = cacheKey.lastIndex(of: ":") else {
        return nil
    }

    let sdkKey = String(cacheKey[cacheKey.index(after: separatorIndex)...])
    guard sdkKey.hasPrefix(sdkKeyPrefix) else {
        return nil
    }

    let baseKey = String(cacheKey[..<separatorIndex])
    guard !baseKey.contains(":") && !baseKey.isEmpty else {
        return nil
    }
    return (baseKey, sdkKey)
}
