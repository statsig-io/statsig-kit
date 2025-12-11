import Foundation

@objc(DynamicConfig)
public final class DynamicConfigObjC: NSObject {
    internal var config: DynamicConfig

    @objc public var name: String {
        config.name
    }

    @objc public var value: [String: Any] {
        config.value
    }

    @objc public var ruleID: String {
        config.ruleID
    }

    @objc public var groupName: String? {
        config.groupName
    }

    @objc public var isUserInExperiment: Bool {
        config.isUserInExperiment
    }

    @objc public var isExperimentActive: Bool {
        config.isExperimentActive
    }

    @objc public var hashedName: String {
        config.hashedName
    }

    @objc public var evaluationDetails: [String: String] {
        var internalDetails = [String: Any]()
        config.evaluationDetails.addToDictionary(&internalDetails)

        var externalDetails = [String: String]()
        for (key, value) in internalDetails {
            externalDetails[key] = "\(value)"
        }

        return externalDetails
    }

    init(withConfig: DynamicConfig) {
        config = withConfig
    }

    @objc public func getArray(forKey: String, defaultValue: [Any]) -> [Any] {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getBool(forKey: String, defaultValue: Bool) -> Bool {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getDictionary(forKey: String, defaultValue: [String: Any]) -> [String: Any] {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getDouble(forKey: String, defaultValue: Double) -> Double {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getInt(forKey: String, defaultValue: Int) -> Int {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getString(forKey: String, defaultValue: String) -> String {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func getNullableString(forKey: String, defaultValue: String?) -> String? {
        return config.getValue(forKey: forKey, defaultValue: defaultValue)
    }

    @objc public func toData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(config)
    }

    @objc public static func fromData(_ data: Data) -> DynamicConfigObjC? {
        let decoder = JSONDecoder()
        let swiftConfig = try? decoder.decode(DynamicConfig.self, from: data)
        guard let swiftConfig = swiftConfig else {
            return nil
        }

        return DynamicConfigObjC(withConfig: swiftConfig)
    }
}
