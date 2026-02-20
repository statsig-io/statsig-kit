import Foundation

enum StorageAdapterReadResult {
    case data(Data)
    case notFound
    case error(Error)
}

struct StorageAdapterWriteOptions: OptionSet {
    let rawValue: Int

    static let withoutOverwriting = StorageAdapterWriteOptions(rawValue: 1 << 0)
    static let createFolderIfNeeded = StorageAdapterWriteOptions(rawValue: 1 << 1)
}

protocol StorageAdapter {
    func read(_ key: [String]) -> StorageAdapterReadResult
    func write(_ value: Data, _ key: [String], options: StorageAdapterWriteOptions)
    func remove(_ key: [String])
    func createFolderIfNeeded(_ key: [String])
}

extension StorageAdapter {
    func write(_ value: Data, _ key: [String]) {
        write(value, key, options: [])
    }

    func createFolderIfNeeded(_ key: [String]) {}
}
