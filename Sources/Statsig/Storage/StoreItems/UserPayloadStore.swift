import Foundation

// TODO: Audit thread-safety across index state and background persistence.

fileprivate let DIRNAME_USER_PAYLOAD = "user-payload"
internal let USER_PAYLOAD_INDEX_FILENAME = "_index.json"

final class UserPayloadStore {

    // MARK: Static

    // NOTE: This is app-specific when running with a bundle. CLI tools/tests may resolve to a
    // shared caches folder. We can consider exposing a root override in the future.
    static var defaultRootDirURL = FileManager
        .default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("statsig-cache")

    private static let storesLock = NSLock()
    private static var storesBySDKKey: [String: UserPayloadStore] = [:]
    private static var migrationPersistenceQueue = DispatchQueue(
        label: "com.statsig.userPayload.persistence.migration",
        qos: .utility,
        attributes: .concurrent
    )

    static func forSDKKey(
        _ sdkKey: String,
        rootDir: URL? = defaultRootDirURL,
        indexData: Data? = nil
    )
        -> UserPayloadStore
    {
        storesLock.withLock {
            if let existing = storesBySDKKey[sdkKey] {
                return existing
            }
            let created = UserPayloadStore(sdkKey: sdkKey, rootDir: rootDir, indexData: indexData)
            storesBySDKKey[sdkKey] = created
            return created
        }
    }

    static func readIndexData(
        sdkKey: String,
        rootDir: URL? = defaultRootDirURL
    ) -> Data? {
        guard let indexFileURL = getIndexFileURL(rootDir, sdkKey) else {
            return nil
        }
        return try? Data(contentsOf: indexFileURL)
    }

    static func getLegacyDirURL(_ rootDir: URL?) -> URL? {
        return rootDir?
            .appendingPathComponent("_legacy")
            .appendingPathComponent(DIRNAME_USER_PAYLOAD)
    }

    /// Unique directory for each SDK key: statsig-cache/${sdkKey}/user-payload
    static func getSDKKeyDirURL(_ rootDir: URL?, _ sdkKey: String) -> URL? {
        return rootDir?
            .appendingPathComponent(sdkKey)
            .appendingPathComponent(DIRNAME_USER_PAYLOAD)
    }

    static func getIndexFileURL(_ rootDir: URL?, _ sdkKey: String) -> URL? {
        return getSDKKeyDirURL(rootDir, sdkKey)?
            .appendingPathComponent(USER_PAYLOAD_INDEX_FILENAME)
    }

    // MARK: Params & Init

    let rootDir: URL?
    let directoryURL: URL?
    let sdkKey: String

    private let persistenceQueue: DispatchQueue
    private let evictionQueue: DispatchQueue
    private let indexStore: UserPayloadIndexStore

    private init(sdkKey: String, rootDir: URL?, indexData: Data?) {
        self.sdkKey = sdkKey
        self.rootDir = rootDir
        self.directoryURL = rootDir?
            .appendingPathComponent(sdkKey)
            .appendingPathComponent(DIRNAME_USER_PAYLOAD)
        let indexFileURL = self.directoryURL?
            .appendingPathComponent(USER_PAYLOAD_INDEX_FILENAME)
        let sdkKeyPrefix = String(sdkKey.dropFirst(7).prefix(4))
        self.persistenceQueue = DispatchQueue(
            label: "com.statsig.userPayload.persistence.\(sdkKeyPrefix)",
            qos: .utility)
        self.evictionQueue = DispatchQueue(
            label: "com.statsig.userPayload.eviction.\(sdkKeyPrefix)",
            qos: .utility)
        self.indexStore = UserPayloadIndexStore(
            sdkKey: sdkKey,
            indexFileURL: indexFileURL,
            initialIndexData: indexData
        )
    }

    // MARK: Utils

    private func filename(for key: UserCacheKey) -> String {
        return key.fullUserHash
    }

    private func userFileURL(_ userCacheKey: UserCacheKey) -> URL? {
        return directoryURL?
            .appendingPathComponent(userCacheKey.fullUserHash)
    }

    // MARK: Write

    func write(key: UserCacheKey, payload: [String: Any]) {
        guard
            let url = userFileURL(key),
            let data = UserPayloadStore.encode(payload)
        else {
            // TODO: Handle errors
            return
        }

        // Update index
        let payloadCount = indexStore.updateIndexForWrite(
            key: key,
            payload: payload
        )

        // Persist payload
        persistenceQueue.async {
            if !url.path.isEmpty {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            // TODO: Handle errors
            try? data.write(to: url, options: .atomic)
        }

        // Persist index
        if payloadCount <= MAX_CACHED_USER_PAYLOADS_PER_KEY {
            indexStore.persistIndexIfAllowed()
        } else {
            scheduleEviction()
        }
    }

    // Used for migration and backwards compatibility
    private static func write(url: URL?, payload: [String: Any], persistenceQueue: DispatchQueue) {
        guard
            let url = url,
            let data = encode(payload)
        else {
            // TODO: Handle errors
            return
        }

        persistenceQueue.async {
            if !url.path.isEmpty {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            // TODO: Handle errors
            try? data.write(to: url, options: .atomic)
        }
    }

    // Used for migrations
    private static func writeForMigration(url: URL, payload: [String: Any]) {
        guard let data = encode(payload) else {
            // TODO: Handle errors
            return
        }

        migrationPersistenceQueue.async {
            // TODO: Handle errors
            try? data.write(to: url, options: .withoutOverwriting)
        }
    }

    // MARK: Read

    func read(key: UserCacheKey) -> [String: Any]? {
        guard let payload = readPayload(key: key) else {
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

    private func readPayload(key: UserCacheKey) -> [String: Any]? {
        if let payload = UserPayloadStore.read(url: userFileURL(key)) {
            return payload
        }

        if let payload = readUsingMappedKey(key: key) {
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

    private func readUsingMappedKey(key: UserCacheKey) -> [String: Any]? {
        guard let mappedKey = indexStore.mappedFullUserHash(v2Key: key.v2) else {
            return nil
        }

        let payloadURL = directoryURL?.appendingPathComponent(mappedKey)
        if let payload = UserPayloadStore.read(url: payloadURL) {
            return payload
        }

        // cacheKeyMapping has a key, but that key doesn't exist in storage. Since
        // writes are async, a mapped payload can temporarily miss before the file
        // is flushed. This function keeps the mapping and lets
        // eviction/reconciliation clean up truly stale entries.
        return nil
    }

    static func read(url: URL?) -> [String: Any]? {
        guard
            let url = url,
            let data = try? Data(contentsOf: url)
        else {
            // TODO: Handle errors
            return nil
        }

        // TODO: Handle errors
        return decode(data)
    }

    // MARK: Delete

    func remove(key: UserCacheKey) {
        guard let url = userFileURL(key) else {
            // TODO: Handle errors
            return
        }

        // TODO: Handle errors
        persistenceQueue.async {
            try? FileManager.default.removeItem(at: url)
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

    static func migrateIfNeeded(
        _ cacheByID: [String: [String: Any]],
        _ cacheKeyMapping: [String: String],
        _ defaults: DefaultsLike,
        _ rootDir: URL? = UserPayloadStore.defaultRootDirURL
    ) {
        guard StorageServiceMigrationStatus.beginMigrationIfNeeded() else { return }

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

            guard let dirURL = getSDKKeyDirURL(rootDir, sdkKey) else { continue }

            try? FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true
            )

            for entry in selectedEntries {
                index.entries[entry.fullUserHash] = IndexEntry(
                    timestamp: Time.parse(entry.payload[InternalStore.evalTimeKey]))
                if let v2Key = reverseCacheKeyMap[sdkKey]?[entry.fullUserHash] {
                    index.cacheKeyMapping[v2Key] = entry.fullUserHash
                }

                UserPayloadStore.writeForMigration(
                    url: dirURL.appendingPathComponent(entry.fullUserHash),
                    payload: entry.payload
                )
            }
            UserPayloadIndexStore.writeForMigration(
                url: dirURL.appendingPathComponent(USER_PAYLOAD_INDEX_FILENAME),
                index: index,
                persistenceQueue: migrationPersistenceQueue
            )
        }

        if let legacyDirURL = UserPayloadStore.getLegacyDirURL(rootDir) {
            // TODO: Handle errors
            try? FileManager.default.createDirectory(
                at: legacyDirURL,
                withIntermediateDirectories: true
            )

            let selectedLegacyEntries =
                legacyEntries
                .sorted { lhs, rhs in
                    Time.parse(lhs.payload[InternalStore.evalTimeKey])
                        > Time.parse(rhs.payload[InternalStore.evalTimeKey])
                }
                .prefix(MAX_CACHED_USER_PAYLOADS_PER_KEY)

            for entry in selectedLegacyEntries {
                UserPayloadStore.writeForMigration(
                    url: legacyDirURL.appendingPathComponent(entry.fullUserHash),
                    payload: entry.payload
                )
            }
        }

        migrationPersistenceQueue.async(flags: .barrier) {
            defaults.removeObject(forKey: UserDefaultsKeys.localStorageKey)
            defaults.removeObject(forKey: UserDefaultsKeys.cacheKeyMappingKey)
            StorageServiceMigrationStatus.markMigrationDone()
        }
    }

    func readLegacy(_ filename: String) -> [String: Any]? {
        return UserPayloadStore.read(
            url: UserPayloadStore.getLegacyDirURL(self.rootDir)?.appendingPathComponent(
                filename))
    }

    func mappedFullUserHash(v2Key: String) -> String? {
        return indexStore.mappedFullUserHash(v2Key: v2Key)
    }

    // MARK: Tests

    func removeAll() {
        guard let dir = directoryURL else { return }

        try? FileManager.default.removeItem(at: dir)
    }

    internal static func removeAll(_ rootDir: URL? = defaultRootDirURL) {
        guard let rootDir = rootDir else { return }

        try? FileManager.default.removeItem(at: rootDir)
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

        if let directoryURL = directoryURL {
            // Delete user payloads
            persistenceQueue.async {
                let fileManager = FileManager.default
                for filename in evicted {
                    let url = directoryURL.appendingPathComponent(filename)
                    try? fileManager.removeItem(at: url)
                }
            }
        }
        indexStore.persistIndexIfAllowed()
    }

    private func scheduleEviction() {
        evictionQueue.async { [weak self] in
            self?.runEviction()
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
