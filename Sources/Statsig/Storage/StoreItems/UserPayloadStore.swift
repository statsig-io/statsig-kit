import Foundation

// TODO: Thread-safety
// TODO: Cache eviction

fileprivate let DIRNAME_USER_PAYLOAD = "user-payload"

struct UserPayloadStore {

    // MARK: Static

    internal static var rootDirectoryURL = FileManager
        .default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("statsig-cache")

    static var legacyDirURL: URL? {
        rootDirectoryURL?
            .appendingPathComponent("_legacy")
            .appendingPathComponent(DIRNAME_USER_PAYLOAD)
    }

    static func userFileURL(sdkKey: String, filename: String) -> URL? {
        return rootDirectoryURL?
            .appendingPathComponent(sdkKey)
            .appendingPathComponent(DIRNAME_USER_PAYLOAD)
            .appendingPathComponent(filename)
    }

    // MARK: Params & Init

    /// Unique directory for each SDK key: statsig-cache/${sdkKey}/user-payload
    let directoryURL: URL?

    init(sdkKey: String) {
        self.directoryURL = UserPayloadStore.rootDirectoryURL?
            .appendingPathComponent(sdkKey)
            .appendingPathComponent(DIRNAME_USER_PAYLOAD)
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
        UserPayloadStore.write(url: userFileURL(key), payload: payload)
    }

    // Used for migration and backwards compatibility
    static func write(sdkKey: String, filename: String, payload: [String: Any]) {
        return write(url: userFileURL(sdkKey: sdkKey, filename: filename), payload: payload)
    }

    // Used for migration and backwards compatibility
    static func write(url: URL?, payload: [String: Any]) {
        guard
            let url = url,
            let data = encode(payload)
        else {
            // TODO: Handle errors
            return
        }

        if !url.path.isEmpty {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        // TODO: Handle errors
        try? data.write(to: url)
    }

    // MARK: Read

    func read(key: UserCacheKey) -> [String: Any]? {
        if let payload = UserPayloadStore.read(url: userFileURL(key)) {
            return payload
        }

        if let payload = UserPayloadStore.readLegacy(key.v2) {
            return payload
        }

        if let payload = UserPayloadStore.readLegacy(key.v1) {
            return payload
        }

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
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Encoding

    private static func encode(_ value: [String: Any]) -> Data? {
        // TODO: Handle errors
        return try? JSONSerialization.data(withJSONObject: value, options: [])
    }

    private static func decode(_ data: Data) -> [String: Any]? {
        // TODO: Handle errors
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }

    // MARK: Migration and Compatibility

    enum MigrationStatus {
        case none
        case pending
        case started
        // NOTE: we could also have a `done` status, but it's not used yet
    }
    static var migrationStatus = MigrationStatus.none
    static let migrationLock = NSLock()

    static func setNeedsMigration() {
        migrationLock.withLock {
            if migrationStatus == .none {
                migrationStatus = .pending
            }
        }
    }

    static func migrateIfNeeded(
        _ cacheByID: [String: [String: Any]],
        _ defaults: DefaultsLike
    ) {
        let shouldMigrate = migrationLock.withLock {
            if migrationStatus != .pending { return false }
            self.migrationStatus = .started
            return true
        }
        guard shouldMigrate else { return }

        for (key, payload) in cacheByID {
            if let parsed = extractSDKKey(from: key) {
                UserPayloadStore.write(
                    sdkKey: parsed.sdkKey,
                    filename: parsed.baseKey,
                    payload: payload
                )
            } else {
                UserPayloadStore.writeLegacy(filename: key, payload: payload)
            }
        }

        defaults.removeObject(forKey: UserDefaultsKeys.localStorageKey)
    }

    static func readLegacy(_ filename: String) -> [String: Any]? {
        return read(url: legacyDirURL?.appendingPathComponent(filename))
    }

    static func writeLegacy(filename: String, payload: [String: Any]) {
        return write(url: legacyDirURL?.appendingPathComponent(filename), payload: payload)
    }

    // MARK: Tests

    func removeAll() {
        guard let dir = directoryURL else { return }

        try? FileManager.default.removeItem(at: dir)
    }

    internal static func removeAll() {
        guard let dir = rootDirectoryURL else { return }

        try? FileManager.default.removeItem(at: dir)
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
