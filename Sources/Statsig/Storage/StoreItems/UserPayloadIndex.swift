import Foundation

internal let MAX_CACHED_USER_PAYLOADS_PER_KEY = 5

struct IndexEntry: Equatable {
    var timestamp: UInt64?
}

struct UserPayloadIndex: Equatable {
    var entries: [String: IndexEntry]
    var cacheKeyMapping: [String: String]

    init(entries: [String: IndexEntry], cacheKeyMapping: [String: String]) {
        self.entries = entries
        self.cacheKeyMapping = cacheKeyMapping
    }

    init(userPayloads: [(key: UserCacheKey, payload: [String: Any])]) {
        var entries: [String: IndexEntry] = [:]
        var cacheKeyMapping: [String: String] = [:]
        for entry in userPayloads {
            let timestamp = Time.parse(entry.payload[InternalStore.evalTimeKey])
            entries[entry.key.fullUserHash] = IndexEntry(timestamp: timestamp)
            cacheKeyMapping[entry.key.v2] = entry.key.fullUserHash
        }
        self.entries = entries
        self.cacheKeyMapping = cacheKeyMapping
    }

    static func empty() -> UserPayloadIndex {
        return UserPayloadIndex(entries: [:], cacheKeyMapping: [:])
    }

    func encode() -> Data? {
        var encodedEntries: [String: [String: Any]] = [:]
        for (key, entry) in entries {
            var entryDict: [String: Any] = [:]
            if let timestamp = entry.timestamp {
                entryDict["timestamp"] = timestamp
            } else {
                entryDict["timestamp"] = NSNull()
            }
            encodedEntries[key] = entryDict
        }

        let dict: [String: Any] = [
            "version": 1,
            "entries": encodedEntries,
            "cacheKeyMapping": cacheKeyMapping,
        ]
        return try? JSONSerialization.data(withJSONObject: dict, options: [])
    }

    static func decode(_ data: Data) -> UserPayloadIndex? {
        guard
            let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let version = dict["version"] as? Int,
            version == 1,
            let entriesDict = dict["entries"] as? [String: [String: Any]]
        else {
            return nil
        }

        var entries: [String: IndexEntry] = [:]
        for (key, entryDict) in entriesDict {
            let timestampValue = entryDict["timestamp"]
            let timestamp = Time.parse(timestampValue)
            entries[key] = IndexEntry(timestamp: timestamp == 0 ? nil : timestamp)
        }

        let mapping = dict["cacheKeyMapping"] as? [String: String] ?? [:]
        return UserPayloadIndex(entries: entries, cacheKeyMapping: mapping)
    }
}

final class UserPayloadIndexStore {
    let sdkKey: String
    let indexFileKey: [String]
    private let storageAdapter: StorageAdapter

    private let indexLock = NSLock()
    private var index: UserPayloadIndex

    init(
        sdkKey: String,
        storageAdapter: StorageAdapter
    ) {
        self.sdkKey = sdkKey
        self.indexFileKey = [sdkKey, USER_PAYLOAD_DIRNAME, USER_PAYLOAD_INDEX_FILENAME]
        self.storageAdapter = storageAdapter
        self.index = Self.readIndex(sdkKey: sdkKey, storageAdapter: storageAdapter).index
    }

    // MARK: Cache Key Mapping

    // TODO: Remove after memoization is implemented
    func mappedFullUserHash(v2Key: String) -> String? {
        indexLock.withLock { index.cacheKeyMapping[v2Key] }
    }

    // MARK: Update index after payload read/write

    @discardableResult
    func updateIndexForWrite(key: UserCacheKey, payloadTimestamp: UInt64?) -> Int {
        return indexLock.withLock {
            index.entries[key.fullUserHash] = IndexEntry(timestamp: payloadTimestamp)
            index.cacheKeyMapping[key.v2] = key.fullUserHash
            return index.entries.count
        }
    }

    // @returns Bool indicating whether the caller should schedule a cache eviction
    func updateIndexForRead(
        key: UserCacheKey,
        payload: [String: Any],
        maxCachedPayloads: Int
    ) -> Bool {
        let timestamp = Self.resolvedTimestamp(payload)
        var hasChanges = false
        var didIncreasePayloadCount = false
        let payloadCount = indexLock.withLock {
            let existing = index.entries[key.fullUserHash]
            if existing == nil {
                didIncreasePayloadCount = true
            }
            if existing?.timestamp != timestamp {
                index.entries[key.fullUserHash] = IndexEntry(timestamp: timestamp)
                hasChanges = true
            }
            if index.cacheKeyMapping[key.v2] != key.fullUserHash {
                index.cacheKeyMapping[key.v2] = key.fullUserHash
                hasChanges = true
            }
            return index.entries.count
        }

        let shouldScheduleEviction =
            hasChanges && didIncreasePayloadCount && payloadCount > maxCachedPayloads

        if hasChanges && !shouldScheduleEviction {
            persistIndexIfAllowed()
            return false
        }

        return shouldScheduleEviction
    }

    /// @returns Bool indicating whether the payload was removed
    func removeMissingPayload(fullUserHash: String) {
        let removed = indexLock.withLock {
            let removed = index.entries.removeValue(forKey: fullUserHash) != nil
            if removed {
                index.cacheKeyMapping =
                    index.cacheKeyMapping.filter { $0.value != fullUserHash }
            }
            return removed
        }
        if removed {
            persistIndexIfAllowed()
        }
    }

    // MARK: Persist functions

    func persistIndexIfAllowed() {
        // Delay persisting the index until migration is done
        if StorageServiceMigrationStatus.isMigrating() {
            return
        }
        persistIndexNow()
    }

    private func persistIndexNow() {
        guard
            let indexData = indexLock.withLock({ index.encode() })
        else {
            return
        }
        let storageAdapter = self.storageAdapter
        let indexFileKey = self.indexFileKey
        StorageService.persistenceQueue.async(flags: .barrier) {
            storageAdapter.write(indexData, indexFileKey, options: .createFolderIfNeeded)
        }
    }

    // MARK: Read/write

    internal static func readIndex(sdkKey: String, storageAdapter: StorageAdapter) -> (
        index: UserPayloadIndex,
        indexFileExists: Bool
    ) {
        let key = UserPayloadStore.sdkDirectoryKey(sdkKey: sdkKey) + [USER_PAYLOAD_INDEX_FILENAME]

        let data: Data
        let readResult = StorageService.persistenceQueue.sync {
            storageAdapter.read(key)
        }
        switch readResult {
        case .data(let readData):
            data = readData
        case .notFound:
            return (UserPayloadIndex.empty(), false)
        case .error:
            return (UserPayloadIndex.empty(), true)
        }

        guard let decoded = UserPayloadIndex.decode(data) else {
            return (UserPayloadIndex.empty(), true)
        }
        return (decoded, true)
    }

    public static func writeForMigration(
        key: [String],
        index: UserPayloadIndex,
        storageAdapter: StorageAdapter
    ) {
        guard let data = index.encode(), !key.isEmpty else { return }
        StorageService.persistenceQueue.async(flags: .barrier) {
            storageAdapter.write(data, key)
        }
    }

    // MARK: Helpers for eviction and migration

    func evictedFilenames(maxCachedPayloads: Int) -> [String] {
        indexLock.withLock {
            if index.entries.count <= maxCachedPayloads {
                return []
            }

            let sortedKeys = index.entries.sorted { lhs, rhs in
                let lhsTime = lhs.value.timestamp ?? 0
                let rhsTime = rhs.value.timestamp ?? 0
                if lhsTime != rhsTime {
                    return lhsTime > rhsTime
                }
                return lhs.key < rhs.key
            }.map(\.key)

            let keepKeys = Set(sortedKeys.prefix(maxCachedPayloads))
            let evicted = sortedKeys.filter { !keepKeys.contains($0) }
            if evicted.isEmpty {
                return []
            }

            for key in evicted {
                index.entries.removeValue(forKey: key)
            }
            let evictedSet = Set(evicted)
            index.cacheKeyMapping =
                index.cacheKeyMapping.filter { !evictedSet.contains($0.value) }
            return evicted
        }
    }

    static func payloadTimestamp(_ payload: [String: Any]) -> UInt64? {
        if let raw = payload[InternalStore.evalTimeKey] {
            let parsed = Time.parse(raw)
            return parsed == 0 ? nil : parsed
        }
        return nil
    }

    static func resolvedTimestamp(_ payload: [String: Any]) -> UInt64 {
        return payloadTimestamp(payload) ?? UInt64(Date().timeIntervalSince1970 * 1000)
    }
}
