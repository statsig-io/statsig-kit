import Foundation

@objc public protocol StorageProvider {
    @objc func read(_ key: String) -> Data?
    @objc func write(_ value: Data, _ key: String)
    @objc func remove(_ key: String)
}

fileprivate let StorageProviderBasedUserDefaultsQueue =
    "com.Statsig.StorageProviderBasedUserDefaults"

class StorageProviderBasedUserDefaults: DefaultsLike {
    internal var dict: AtomicDictionary<Any?> = AtomicDictionary(
        label: StorageProviderBasedUserDefaultsQueue)
    private let storageProvider: StorageProvider

    init(storageProvider: StorageProvider) {
        self.storageProvider = storageProvider
        readFromStorageProvider()
    }

    func array(forKey key: String) -> [Any]? {
        return getValue(forKey: key) as? [Any]
    }

    func string(forKey key: String) -> String? {
        return getValue(forKey: key) as? String
    }

    func dictionary(forKey key: String) -> [String: Any]? {
        return getValue(forKey: key) as? [String: Any]
    }

    func data(forKey key: String) -> Data? {
        return getValue(forKey: key) as? Data
    }

    func removeObject(forKey key: String) {
        dict[key] = nil
        writeToStorageProvider()
    }

    func setValue(_ value: Any?, forKey: String) {
        set(value, forKey: forKey)
    }

    func set(_ value: Any?, forKey key: String) {
        dict[key] = value
        writeToStorageProvider()
    }

    func synchronize() -> Bool {
        writeToStorageProvider()
        return true
    }

    func keys() -> [String] {
        return dict.keys()
    }

    func setDictionarySafe(_ dict: [String: Any], forKey key: String) {
        set(dict, forKey: key)
    }

    func dictionarySafe(forKey key: String) -> [String: Any]? {
        return dictionary(forKey: key)
    }

    private func getValue(forKey key: String) -> Any? {
        return dict[key] as? Any
    }

    private func writeToStorageProvider() {
        if let data = dict.toData() {
            storageProvider.write(data, "com.statsig.cache")
        } else {
            PrintHandler.log("[Statsig]: Failed to write data to storage provider.")
            return
        }
    }

    private func readFromStorageProvider() {
        if let data = storageProvider.read("com.statsig.cache") {
            dict = AtomicDictionary.fromData(data, label: StorageProviderBasedUserDefaultsQueue)
        } else {
            dict = AtomicDictionary(label: StorageProviderBasedUserDefaultsQueue)
        }
    }
}
