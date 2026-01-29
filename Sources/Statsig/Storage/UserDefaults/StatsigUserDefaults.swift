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

class StatsigUserDefaults {
    static var defaults: DefaultsLike = UserDefaults.standard
}
