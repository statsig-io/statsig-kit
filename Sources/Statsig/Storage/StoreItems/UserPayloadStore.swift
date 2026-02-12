import Foundation

// TODO: Thread-safety
// TODO: Cache eviction
// TODO: Read old non-migrated payloads
// TODO: Read migrated payloads with old keys (v1 or v2)

struct UserPayloadStore {

    // MARK: Static

    private static let rootDirectoryURL = FileManager
        .default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("statsig-cache")

    // MARK: Params & Init

    /// Unique directory for each SDK key: statsig-cache/${sdkKey}/user-payload
    let directoryURL: URL?

    init(sdkKey: String) {
        self.directoryURL = UserPayloadStore.rootDirectoryURL?
            .appendingPathComponent(sdkKey)
            .appendingPathComponent("user-payload")
    }

    // MARK: Utils

    private func filename(for key: UserCacheKey) -> String {
        return key.fullUserHash
    }

    private func userFileURL(_ fullUserHash: String) -> URL? {
        return directoryURL?
            .appendingPathComponent(fullUserHash)
    }

    // MARK: Write

    func write(key: UserCacheKey, payload: [String: Any]) {
        return write(filename: filename(for: key), payload: payload)
    }

    // Will be used for migration and backwards compatibility
    func write(filename: String, payload: [String: Any]) {
        guard
            let url = userFileURL(filename),
            let data = encode(payload)
        else {
            // TODO: Handle errors
            return
        }

        if let dir = directoryURL {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        // TODO: Handle errors
        try? data.write(to: url)
    }

    // MARK: Read

    func read(key: UserCacheKey) -> [String: Any]? {
        return read(filename: filename(for: key))
    }

    // Will be used for migration and backwards compatibility
    func read(filename: String) -> [String: Any]? {
        guard
            let url = userFileURL(filename),
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
        return remove(filename: filename(for: key))

    }

    func remove(filename: String) {
        guard let url = userFileURL(filename) else {
            // TODO: Handle errors
            return
        }

        // TODO: Handle errors
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Encoding

    private func encode(_ value: [String: Any]) -> Data? {
        // TODO: Handle errors
        return try? JSONSerialization.data(withJSONObject: value, options: [])
    }

    private func decode(_ data: Data) -> [String: Any]? {
        // TODO: Handle errors
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
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
