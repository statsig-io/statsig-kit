import Foundation

fileprivate let failedRequestStoreFilename = "failed-log-requests"

struct FailedLogRequest: Codable, Equatable {
    let body: Data
    let lastFailedAtMs: UInt64
    // The number of events currently encoded in this request body. This is only used
    // if the request itself is later trimmed out of the failed-request store.
    let requestEventCount: Int

    func withLastFailedAtMs(_ lastFailedAtMs: UInt64) -> FailedLogRequest {
        FailedLogRequest(
            body: body,
            lastFailedAtMs: lastFailedAtMs,
            requestEventCount: requestEventCount
        )
    }

    static func makeRequests(
        from bodies: [Data],
        lastFailedAtMs: UInt64,
        requestEventCount: Int
    ) -> [FailedLogRequest] {
        bodies.map {
            FailedLogRequest(
                body: $0,
                lastFailedAtMs: lastFailedAtMs,
                requestEventCount: requestEventCount
            )
        }
    }
}

struct DroppedLogRequestSummary: Codable, Equatable {
    var eventCount: Int
    var lastFailedAtMs: UInt64

    func makeEvent() -> Event {
        Event(
            user: nil,
            name: "dropped_log_event.count",
            value: Double(eventCount),
            metadata: nil,
            time: lastFailedAtMs,
            disableCurrentVCLogging: true
        )
    }

    mutating func merge(_ request: FailedLogRequest) {
        eventCount += request.requestEventCount
        lastFailedAtMs = max(lastFailedAtMs, request.lastFailedAtMs)
    }

    static func from(_ requests: [FailedLogRequest]) -> DroppedLogRequestSummary? {
        guard let firstRequest = requests.first else {
            return nil
        }

        var summary = DroppedLogRequestSummary(
            eventCount: firstRequest.requestEventCount,
            lastFailedAtMs: firstRequest.lastFailedAtMs
        )
        for request in requests.dropFirst() {
            summary.merge(request)
        }

        return summary
    }
}

struct FailedLogRequestStoreData: Codable, Equatable {
    var requests: [FailedLogRequest]
    var pendingDroppedRequestSummary: DroppedLogRequestSummary?

    var isEmpty: Bool {
        requests.isEmpty && pendingDroppedRequestSummary == nil
    }

    func encode() -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(self)
    }

    static func decode(_ data: Data) -> FailedLogRequestStoreData? {
        try? PropertyListDecoder().decode(FailedLogRequestStoreData.self, from: data)
    }

}

final class FailedLogRequestStore {

    // MARK: Static

    #if os(tvOS)
    static let defaultMaxStoreSizeBytes = 100_000  // 100 KB
    #else
    static let defaultMaxStoreSizeBytes = 1_000_000  // 1 MB
    #endif

    private static let storesLock = NSLock()
    private static var storesBySDKKey: [String: FailedLogRequestStore] = [:]

    static func forSDKKey(
        _ sdkKey: String,
        storageProvider: StorageProvider? = nil,
        userDefaults: DefaultsLike = StatsigUserDefaults.defaults,
        maxStoreSizeBytes: Int = defaultMaxStoreSizeBytes
    ) -> FailedLogRequestStore {
        forSDKKey(
            sdkKey,
            storageAdapter: storageProvider.map {
                StorageProviderToAdapter(storageProvider: $0)
            } ?? FileStorageAdapter(),
            userDefaults: userDefaults,
            maxStoreSizeBytes: maxStoreSizeBytes
        )
    }

    static func forSDKKey(
        _ sdkKey: String,
        storageAdapter: StorageAdapter,
        userDefaults: DefaultsLike = StatsigUserDefaults.defaults,
        maxStoreSizeBytes: Int = defaultMaxStoreSizeBytes
    ) -> FailedLogRequestStore {
        storesLock.withLock {
            if let existing = storesBySDKKey[sdkKey] {
                return existing
            }

            let created = FailedLogRequestStore(
                sdkKey: sdkKey,
                storageAdapter: storageAdapter,
                userDefaults: userDefaults,
                maxStoreSizeBytes: maxStoreSizeBytes
            )
            storesBySDKKey[sdkKey] = created
            return created
        }
    }

    static func storagePath(sdkKey: String) -> [String] {
        [
            sdkKey,
            failedRequestStoreFilename,
        ]
    }

    static func deleteLocalStorage(
        sdkKey: String,
        storageAdapter: StorageAdapter? = nil
    ) {
        let cachedStore = storesLock.withLock {
            storesBySDKKey.removeValue(forKey: sdkKey)
        }

        let path = storagePath(sdkKey: sdkKey)
        cachedStore?.storageAdapter.remove(path)
        storageAdapter?.remove(path)
        FileStorageAdapter().remove(path)
    }

    internal static func clearCachedInstances() {
        storesLock.withLock {
            storesBySDKKey.removeAll()
        }
    }

    // MARK: Params & Init

    let sdkKey: String
    let storageAdapter: StorageAdapter
    let lock = NSLock()
    let maxStoreSizeBytes: Int

    private var store: FailedLogRequestStoreData

    private init(
        sdkKey: String,
        storageAdapter: StorageAdapter,
        userDefaults: DefaultsLike,
        maxStoreSizeBytes: Int
    ) {
        self.sdkKey = sdkKey
        self.storageAdapter = storageAdapter
        self.maxStoreSizeBytes = maxStoreSizeBytes
        let loadedStore = Self.loadStore(
            sdkKey: sdkKey,
            storageAdapter: storageAdapter,
            userDefaults: userDefaults
        )
        self.store = loadedStore.store
        if loadedStore.didMigrateUserDefaultsRequests {
            persist()
        }
    }

    // MARK: Read

    var requests: [FailedLogRequest] {
        lock.withLock { store.requests }
    }

    var pendingDroppedRequestSummary: DroppedLogRequestSummary? {
        lock.withLock { store.pendingDroppedRequestSummary }
    }

    // MARK: Write

    func addRequest(
        _ requestData: Data?,
        lastFailedAtMs: UInt64,
        requestEventCount: Int,
        persist: Bool = true
    ) {
        guard let requestData = requestData else {
            return
        }

        addRequests(
            [
                FailedLogRequest(
                    body: requestData,
                    lastFailedAtMs: lastFailedAtMs,
                    requestEventCount: requestEventCount
                )
            ],
            persist: persist
        )
    }

    func addRequests(
        from requestData: [Data],
        lastFailedAtMs: UInt64,
        requestEventCount: Int,
        persist: Bool = true
    ) {
        addRequests(
            FailedLogRequest.makeRequests(
                from: requestData,
                lastFailedAtMs: lastFailedAtMs,
                requestEventCount: requestEventCount
            ),
            persist: persist
        )
    }

    func addRequests(_ requests: [FailedLogRequest], persist: Bool = true) {
        guard !requests.isEmpty else { return }

        lock.withLock {
            store.requests += requests
            trimToFitLocked()
            if persist {
                persistLocked()
            }
        }
    }

    func addOrUpdateRequest(
        _ requestData: Data?,
        lastFailedAtMs: UInt64,
        requestEventCount: Int,
        persist: Bool = true
    ) {
        guard let requestData = requestData else {
            return
        }

        lock.withLock {
            for (i, req) in store.requests.enumerated() {
                if req.body == requestData {
                    store.requests[i] = req.withLastFailedAtMs(lastFailedAtMs)
                    if persist {
                        persistLocked()
                    }
                    return
                }
            }

            store.requests.append(
                FailedLogRequest(
                    body: requestData,
                    lastFailedAtMs: lastFailedAtMs,
                    requestEventCount: requestEventCount
                )
            )
            trimToFitLocked()
            if persist {
                persistLocked()
            }
        }
    }

    func takeRequest(_ requestData: Data) -> FailedLogRequest? {
        lock.withLock {
            for (i, req) in store.requests.enumerated() {
                if req.body == requestData {
                    store.requests.remove(at: i)
                    persistLocked()
                    return req
                }
            }

            return nil
        }
    }

    func takeRequestsForRetry() -> [FailedLogRequest] {
        lock.withLock {
            let requests = takeRequestsLocked()
            persistLocked()
            return requests
        }
    }

    func takePendingDroppedRequestSummary() -> DroppedLogRequestSummary? {
        lock.withLock {
            let summary = store.pendingDroppedRequestSummary
            guard summary != nil else {
                return nil
            }

            store.pendingDroppedRequestSummary = nil
            persistLocked()
            return summary
        }
    }

    func restorePendingDroppedRequestSummary(_ summary: DroppedLogRequestSummary) {
        lock.withLock {
            if var existingSummary = store.pendingDroppedRequestSummary {
                existingSummary.eventCount += summary.eventCount
                existingSummary.lastFailedAtMs = max(
                    existingSummary.lastFailedAtMs,
                    summary.lastFailedAtMs
                )
                store.pendingDroppedRequestSummary = existingSummary
            } else {
                store.pendingDroppedRequestSummary = summary
            }
            persistLocked()
        }
    }

    func persist() {
        lock.withLock {
            persistLocked()
        }
    }

    // MARK: Persistence

    private func trimToFitLocked() {
        var totalBodyBytes = store.requests.reduce(0) { partialResult, request in
            partialResult + request.body.count
        }

        guard totalBodyBytes > maxStoreSizeBytes else {
            return
        }

        var updatedSummary = store.pendingDroppedRequestSummary
        store.pendingDroppedRequestSummary = nil
        var remainingRequests = takeRequestsLocked()

        while totalBodyBytes > maxStoreSizeBytes, !remainingRequests.isEmpty {
            let removedRequest = remainingRequests.removeFirst()
            if var summary = updatedSummary {
                summary.merge(removedRequest)
                updatedSummary = summary
            } else {
                updatedSummary = DroppedLogRequestSummary.from([removedRequest])
            }
            totalBodyBytes -= removedRequest.body.count
        }

        restoreRequestsLocked(remainingRequests)

        if let updatedSummary {
            store.pendingDroppedRequestSummary = updatedSummary
        }
    }

    private func takeRequestsLocked() -> [FailedLogRequest] {
        let requests = store.requests
        store.requests = []
        return requests
    }

    private func restoreRequestsLocked(_ requests: [FailedLogRequest]) {
        store.requests = requests
    }

    // Syncs the in-memory store to the storage adapter, removing the persisted file when empty.
    private func persistLocked() {
        if store.isEmpty {
            storageAdapter.remove(Self.storagePath(sdkKey: sdkKey))
            return
        }

        guard let encodedStore = store.encode() else {
            return
        }

        storageAdapter.write(
            encodedStore,
            Self.storagePath(sdkKey: sdkKey),
            options: .createFolderIfNeeded
        )
    }

    private static func loadStore(
        sdkKey: String,
        storageAdapter: StorageAdapter,
        userDefaults: DefaultsLike
    ) -> (store: FailedLogRequestStoreData, didMigrateUserDefaultsRequests: Bool) {
        let storePath = storagePath(sdkKey: sdkKey)
        var store = FailedLogRequestStoreData(requests: [], pendingDroppedRequestSummary: nil)

        switch storageAdapter.read(storePath) {
        case .data(let data):
            if let decodedStore = FailedLogRequestStoreData.decode(data) {
                store = decodedStore
            }
        case .notFound, .error:
            break
        }

        let userDefaultsRequests = loadUserDefaultsRequests(
            sdkKey: sdkKey,
            userDefaults: userDefaults
        )
        if !userDefaultsRequests.isEmpty {
            store.requests = userDefaultsRequests + store.requests
        }

        return (store, !userDefaultsRequests.isEmpty)
    }

    private static func loadUserDefaultsRequests(
        sdkKey: String,
        userDefaults: DefaultsLike
    ) -> [FailedLogRequest] {
        let userDefaultsStorageKey = UserDefaultsKeys.getFailedEventsStorageKey(sdkKey)
        guard
            let userDefaultsRequests = userDefaults.array(
                forKey: userDefaultsStorageKey)
        else {
            return []
        }

        userDefaults.removeObject(forKey: userDefaultsStorageKey)
        _ = userDefaults.synchronize()

        let migratedAtMs = Time.now()
        return userDefaultsRequests.compactMap { userDefaultsRequest in
            guard let requestBody = userDefaultsRequest as? Data else {
                return nil
            }

            return FailedLogRequest(
                body: requestBody,
                lastFailedAtMs: migratedAtMs,
                requestEventCount: 0
            )
        }
    }
}
