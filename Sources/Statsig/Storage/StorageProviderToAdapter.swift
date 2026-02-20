import Foundation

final class StorageProviderToAdapter: StorageAdapter {
    private let storageProvider: StorageProvider

    init(storageProvider: StorageProvider) {
        self.storageProvider = storageProvider
    }

    func read(_ key: [String]) -> StorageAdapterReadResult {
        guard let data = storageProvider.read(encodeKey(key)) else {
            return .notFound
        }
        return .data(data)
    }

    func write(_ value: Data, _ key: [String], options: StorageAdapterWriteOptions = []) {
        // NOTE: StorageProvider has no atomic "write-if-absent" primitive.
        if options.contains(.withoutOverwriting), case .data = read(key) {
            return
        }
        storageProvider.write(value, encodeKey(key))
    }

    func remove(_ key: [String]) {
        storageProvider.remove(encodeKey(key))
    }

    private func encodeKey(_ key: [String]) -> String {
        return key.joined(separator: ".")
    }
}
