import Foundation

protocol DefaultsLike {
    func array(forKey defaultName: String) -> [Any]?
    func string(forKey defaultName: String) -> String?
    func dictionary(forKey defaultName: String) -> [String: Any]?
    func data(forKey defaultName: String) -> Data?
    func removeObject(forKey defaultName: String)
    func setValue(_ value: Any?, forKey: String)
    func set(_ value: Any?, forKey: String)
    func synchronize() -> Bool
    func keys() -> [String]

    func setDictionarySafe(_ dict: [String: Any], forKey key: String)
    func dictionarySafe(forKey key: String) -> [String: Any]?
}

extension UserDefaults: DefaultsLike {
    func setDictionarySafe(_ dict: [String: Any], forKey key: String) {
        guard JSONSerialization.isValidJSONObject(dict),
            let json = try? JSONSerialization.data(withJSONObject: dict)
        else {
            PrintHandler.log("[Statsig]: Failed to save to cache")
            return
        }

        set(json, forKey: key)
    }

    func dictionarySafe(forKey key: String) -> [String: Any]? {
        do {
            guard let data = data(forKey: key) else {
                return nil
            }

            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            return dict
        } catch {
            return nil
        }
    }

    func keys() -> [String] {
        return dictionaryRepresentation().keys.sorted()
    }
}

fileprivate final class WeakProviderDefaults {
    weak var value: StorageProviderBasedUserDefaults?

    init(_ value: StorageProviderBasedUserDefaults) {
        self.value = value
    }
}

class StatsigUserDefaults {
    private static let defaultsLock = NSLock()
    private static var currentDefaults: DefaultsLike = UserDefaults.standard
    static var defaults: DefaultsLike {
        get { defaultsLock.withLock { currentDefaults } }
        set { defaultsLock.withLock { currentDefaults = newValue } }
    }

    // All file-backed clients must share a single in-memory snapshot and write queue.
    static let fileDefaults = FileBasedUserDefaults()
    private static let fileSelectionLock = NSLock()
    private static var providerDefaults: [ObjectIdentifier: WeakProviderDefaults] = [:]

    private static func previousDefaults() -> DefaultsLike {
        let current = defaults
        return current is FileBasedUserDefaults || current is StorageProviderBasedUserDefaults
            ? UserDefaults.standard : current
    }

    private static func carryStableID(to selected: DefaultsLike) {
        guard selected.string(forKey: UserDefaultsKeys.stableIDKey)?.isEmpty != false,
            let stableID = previousDefaults().string(forKey: UserDefaultsKeys.stableIDKey),
            !stableID.isEmpty
        else { return }
        selected.setValue(stableID, forKey: UserDefaultsKeys.stableIDKey)
    }

    static func resolve(_ options: StatsigOptions?) -> (defaults: DefaultsLike, type: CacheType) {
        if options?.enableCacheByFile == true {
            return fileSelectionLock.withLock {
                let selectedDefaults = Self.fileDefaults
                // Only the stable ID crosses from the old cache. Values stay cold.
                carryStableID(to: selectedDefaults)
                return (selectedDefaults, CacheType.file)
            }
        }

        if let storageProvider = options?.storageProvider {
            return fileSelectionLock.withLock {
                providerDefaults = providerDefaults.filter { $0.value.value != nil }
                let identity = ObjectIdentifier(storageProvider as AnyObject)
                let selectedDefaults: StorageProviderBasedUserDefaults
                if let cached = providerDefaults[identity]?.value {
                    selectedDefaults = cached
                } else if let current = defaults as? StorageProviderBasedUserDefaults,
                    current.wraps(storageProvider)
                {
                    selectedDefaults = current
                    providerDefaults[identity] = WeakProviderDefaults(current)
                } else {
                    selectedDefaults = StorageProviderBasedUserDefaults(
                        storageProvider: storageProvider)
                    providerDefaults[identity] = WeakProviderDefaults(selectedDefaults)
                }
                carryStableID(to: selectedDefaults)
                return (selectedDefaults, CacheType.provider)
            }
        }

        return (previousDefaults(), .user_defaults)
    }
}
