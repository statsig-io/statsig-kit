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

fileprivate func payloadTimestamp(_ payload: [String: Any]) -> UInt64? {
    if let raw = payload[InternalStore.evalTimeKey] {
        let parsed = Time.parse(raw)
        return parsed == 0 ? nil : parsed
    }
    return nil
}

fileprivate func resolvedTimestamp(_ payload: [String: Any]) -> UInt64 {
    return payloadTimestamp(payload) ?? UInt64(Date().timeIntervalSince1970 * 1000)
}

final class UserPayloadIndexStore {
    let sdkKey: String
    let indexFileURL: URL?
    private let indexPersistenceQueue: DispatchQueue

    private let indexLock = NSLock()
    private var index: UserPayloadIndex

    init(
        sdkKey: String,
        indexFileURL: URL?
    ) {
        self.sdkKey = sdkKey
        self.indexFileURL = indexFileURL
        self.indexPersistenceQueue = DispatchQueue(
            label:
                "com.statsig.userPayload.index.persistence.\(String(sdkKey.dropFirst(7).prefix(4)))",
            qos: .utility
        )

        let loadedIndex = UserPayloadIndexStore.readIndex(from: indexFileURL)
        self.index = loadedIndex.index
        if loadedIndex.indexFileExists {
            StorageServiceMigrationStatus.markMigrationDone()
        }
    }

    // MARK: Cache Key Mapping

    // TODO: Remove after memoization is implemented
    func mappedFullUserHash(v2Key: String) -> String? {
        indexLock.withLock { index.cacheKeyMapping[v2Key] }
    }

    // MARK: Update index after payload read/write

    @discardableResult
    func updateIndexForWrite(key: UserCacheKey, payload: [String: Any]) -> Int {
        let timestamp = payloadTimestamp(payload)
        return indexLock.withLock {
            index.entries[key.fullUserHash] = IndexEntry(timestamp: timestamp)
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
        let timestamp = resolvedTimestamp(payload)
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
        if StorageServiceMigrationStatus.isMigrationInProgress() {
            return
        }
        persistIndexNow()
    }

    private func persistIndexNow() {
        guard
            let indexURL = indexFileURL,
            let indexData = indexLock.withLock({ index.encode() })
        else {
            return
        }
        indexPersistenceQueue.async {
            // Handle errors
            try? FileManager.default.createDirectory(
                at: indexURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? indexData.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Read/write

    private static func readIndex(from url: URL?) -> (
        index: UserPayloadIndex,
        indexFileExists: Bool
    ) {
        guard let url = url else {
            return (UserPayloadIndex.empty(), false)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            let missingFileError =
                nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
            return (UserPayloadIndex.empty(), !missingFileError)
        }

        guard let decoded = UserPayloadIndex.decode(data) else {
            return (UserPayloadIndex.empty(), true)
        }
        return (decoded, true)
    }

    // FIXME: writeForMigration uses a different queue than persistIndexNow.
    public static func writeForMigration(
        url: URL, index: UserPayloadIndex, persistenceQueue: DispatchQueue
    ) {
        guard let data = index.encode() else { return }
        persistenceQueue.async {
            // TODO: Handle errors
            try? data.write(to: url, options: .atomic)
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
}
