import Foundation

final class FileStorageAdapter: StorageAdapter {
    static var defaultRootDirectory = FileManager
        .default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("statsig-cache", isDirectory: true)

    private enum StorageAdapterError: Error {
        case invalidKey
    }

    private let rootDirectory: URL?

    init(rootDirectory: URL? = defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    func read(_ key: [String]) -> StorageAdapterReadResult {
        guard let url = url(for: key, isDirectory: false) else {
            return .error(StorageAdapterError.invalidKey)
        }

        do {
            return .data(try Data(contentsOf: url))
        } catch {
            let nsError = error as NSError
            let isMissingFile =
                nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
            return isMissingFile ? .notFound : .error(error)
        }
    }

    func write(_ value: Data, _ key: [String], options: StorageAdapterWriteOptions = []) {
        guard let url = url(for: key, isDirectory: false) else {
            return
        }

        if options.contains(.createFolderIfNeeded) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try? value.write(
            to: url,
            options: options.contains(.withoutOverwriting) ? .withoutOverwriting : .atomic
        )
    }

    func remove(_ key: [String]) {
        guard let url = url(for: key, isDirectory: false) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    func createFolderIfNeeded(_ key: [String]) {
        guard let url = url(for: key, isDirectory: true) else { return }

        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private func url(for key: [String], isDirectory: Bool) -> URL? {
        guard let rootDirectory = rootDirectory, !key.isEmpty else {
            return nil
        }

        let lastIndex = key.index(before: key.endIndex)
        return key.enumerated().reduce(rootDirectory) { (partial, tuple) in
            partial.appendingPathComponent(
                tuple.element,
                isDirectory: tuple.offset == lastIndex ? isDirectory : true
            )
        }
    }
}
