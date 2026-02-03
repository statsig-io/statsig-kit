import Foundation

fileprivate let FileBasedUserDefaultsQueue = "com.Statsig.FileBasedUserDefaults"

class FileBasedUserDefaults: DefaultsLike {
    private let cacheURL = FileManager
        .default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("statsig-cache-data")

    private var dict: AtomicDictionary<Any?> = AtomicDictionary(label: FileBasedUserDefaultsQueue)

    internal var persistenceDispatchQueue = DispatchQueue(
        label: "com.Statsig.FileBasedUserDefaults.Persistence",
        qos: .default,
        attributes: [])

    init() {
        readFromDisk()
    }

    func array(forKey defaultName: String) -> [Any]? {
        getValue(forKey: defaultName) as? [Any]
    }

    func string(forKey defaultName: String) -> String? {
        getValue(forKey: defaultName) as? String
    }

    func dictionary(forKey defaultName: String) -> [String: Any]? {
        getValue(forKey: defaultName) as? [String: Any]
    }

    func data(forKey defaultName: String) -> Data? {
        getValue(forKey: defaultName) as? Data
    }

    func removeObject(forKey key: String) {
        let url = cacheURL

        dict.setValueAndGetDataAsync(
            value: nil, forKey: key, dispatchQueue: persistenceDispatchQueue
        ) { data in
            guard let data = data, let url = url else {
                PrintHandler.log("[Statsig]: Failed to write data to storage provider.")
                return
            }
            do {
                try data.write(to: url)
            } catch {
                PrintHandler.log("[Statsig]: Failed to write data to storage provider.")
                return
            }
        }
    }

    func setValue(_ value: Any?, forKey key: String) {
        set(value, forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        let url = cacheURL

        dict.setValueAndGetDataAsync(
            value: value, forKey: key, dispatchQueue: persistenceDispatchQueue
        ) { data in
            guard let data = data, let url = url else {
                PrintHandler.log("[Statsig]: Failed to write data to storage provider.")
                return
            }
            do {
                try data.write(to: url)
            } catch {
                PrintHandler.log("[Statsig]: Failed to write data to storage provider.")
                return
            }
        }
    }

    func synchronize() -> Bool {
        return writeToDisk()
    }

    func keys() -> [String] {
        return dict.keys()
    }

    func setDictionarySafe(_ dict: [String: Any], forKey key: String) {
        // File storage doesn't actaully need this Safe func call, just call the standard .set
        set(dict, forKey: key)
    }

    func dictionarySafe(forKey key: String) -> [String: Any]? {
        // File storage doesn't actaully need this Safe func call, just call the standard .dictionary
        return dictionary(forKey: key)
    }

    private func getValue(forKey key: String) -> Any? {
        return dict[key] as? Any
    }

    private func writeToDisk() -> Bool {
        guard let url = cacheURL else {
            return false
        }

        let data = dict.toData()

        do {
            try persistenceDispatchQueue.sync {
                try data?.write(to: url)
            }
        } catch {
            return false
        }

        return true
    }

    private func readFromDisk() {
        guard let url = cacheURL else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            dict = AtomicDictionary.fromData(data, label: FileBasedUserDefaultsQueue)
        } catch {
            return
        }
    }
}
