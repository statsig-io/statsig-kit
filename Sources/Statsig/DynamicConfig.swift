import Foundation

/**
 Class that surfaces the current experiment/dynamic config/autotune values from Statsig.

 SeeAlso [Dynamic Config Documentation](https://docs.statsig.com/dynamic-config)

 SeeAlso [Experiments Documentation](https://docs.statsig.com/experiments-plus)
 */
public struct DynamicConfig: ConfigBase, ConfigProtocol {
    /**
     The name used to retrieve this DynamicConfig
     */
    public let name: String

    /**
     The values stored
     */
    public let value: [String: Any]

    /**
     The ID of the rule that lead to the resulting dynamic config.
     */
    public let ruleID: String

    /**
     The group name associated with this dynamic config.
     */
    public let groupName: String?

    let secondaryExposures: [[String: String]]

    /**
     (Experiments Only) Is the current user allocated to this experiment
     */
    public let isUserInExperiment: Bool

    /**
     (Experiments Only) Is this experiment currently running
     */
    public let isExperimentActive: Bool

    /**
     Whether the user passed or failed the rule evaluation
     */
    public let didPassRule: Bool

    /**
     The SHA256 hash of this configs name
     */
    public let hashedName: String

    /**
     (For debug purposes) Why did Statsig return this DynamicConfig
     */
    public let evaluationDetails: EvaluationDetails

    var isDeviceBased: Bool = false
    var rawValue: [String: Any] = [:]

    public var keys: [String: Any].Keys {
        return value.keys
    }

    internal init(name: String, configObj: [String: Any] = [:], evalDetails: EvaluationDetails) {
        self.init(configName: name, configObj: configObj, evalDetails: evalDetails)
    }

    internal init(
        configName: String,
        configObj: [String: Any] = [:],
        evalDetails: EvaluationDetails
    ) {
        self.name = configName
        self.ruleID = configObj["rule_id"] as? String ?? ""
        self.groupName = configObj["group_name"] as? String
        self.value = configObj["value"] as? [String: Any] ?? [:]
        self.secondaryExposures = configObj["secondary_exposures"] as? [[String: String]] ?? []
        self.hashedName = configObj["name"] as? String ?? ""

        self.isDeviceBased = configObj["is_device_based"] as? Bool ?? false
        self.isUserInExperiment = configObj["is_user_in_experiment"] as? Bool ?? false
        self.isExperimentActive = configObj["is_experiment_active"] as? Bool ?? false
        self.didPassRule = configObj["passed"] as? Bool ?? false
        self.rawValue = configObj

        self.evaluationDetails = evalDetails
    }

    internal init(
        configName: String,
        value: [String: Any],
        ruleID: String,
        evalDetails: EvaluationDetails,
        secondaryExposures: [[String: String]]? = nil,
        isExperimentActive: Bool? = nil,
        isUserInExperiment: Bool? = nil,
        didPassRule: Bool? = nil
    ) {
        self.name = configName
        self.value = value
        self.ruleID = ruleID
        self.groupName = nil
        self.secondaryExposures = secondaryExposures ?? []
        self.hashedName = ""

        self.isExperimentActive = isExperimentActive ?? false
        self.isUserInExperiment = isUserInExperiment ?? false
        self.didPassRule = didPassRule ?? false

        self.evaluationDetails = evalDetails
    }


    
    /**
     Get the value for the given key, falling back to the defaultValue if it cannot be found or is of a different type.

     Parameters:
     - forKey: The key of parameter being fetched
     - defaultValue: The fallback value if the key cannot be found
     */
    public func getValue<T: StatsigDynamicConfigValue>(forKey key: String, defaultValue: T) -> T {
        return getValueImpl(forKey: key, defaultValue: defaultValue) ?? defaultValue
    }

    /**
     Get the value for the given key, falling back to nil if it cannot be found or is of a different type.
     If you get the error "Generic parameter 'T' could not be inferred", here are a few ways to fix it:
     1. Set the type on the variable definition `let a: String? = layer.getValue(...)`
     2. Cast to the type you need `let a = layer.getValue(...) as String?`
     3. Add the defaultValue parameter: `let a = layer.getValue(forKey:"key", defaultValue: "")`.

     Parameters:
     - forKey: The key of parameter being fetched
     */
    public func getValue<T: StatsigDynamicConfigValue>(forKey key: String) -> T? {
        return getValueImpl(forKey: key)
    }

    internal func getValueImpl<T: StatsigDynamicConfigValue>(forKey key: String, defaultValue: T? = nil) -> T? {
        let returningLog = defaultValue == nil ? "nil" : "the defaultValue"
        guard let result = value[key] else {
            PrintHandler.log("[Statsig]: \(key) does not exist in this Dynamic Config. Returning \(returningLog).")
            return defaultValue
        }
    
        guard let result = result as? T else {
            PrintHandler.log("[Statsig]: \(key) exists in this Dynamic Config, but requested type was incorrect (Requested = \(T.self), Actual = \(type(of: result))). Returning \(returningLog).")
            return defaultValue
        }
        
        return result
    }

    internal static func empty(
        _ name: String,
        _ evalDetails: EvaluationDetails
    ) -> DynamicConfig {
        return DynamicConfig(
            name: name,
            evalDetails: evalDetails
        )
    }
}

extension DynamicConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case value
        case ruleID
        case groupName
        case evaluationDetails
        case secondaryExposures
        case didPassRule
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decode(String.self, forKey: .name)

        let data = try container.decode(Data.self, forKey: .value)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        self.value = dict ?? [:]
        self.ruleID = try container.decode(String.self, forKey: .ruleID)
        self.groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        self.secondaryExposures = try container.decode([[String: String]].self, forKey: .secondaryExposures)
        self.evaluationDetails = try container.decode(EvaluationDetails.self, forKey: .evaluationDetails)
        self.didPassRule = try container.decode(Bool.self, forKey: .didPassRule)

        self.hashedName = ""
        self.isExperimentActive = false
        self.isUserInExperiment = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)

        let json = try JSONSerialization.data(withJSONObject: value)
        try container.encode(json, forKey: .value)

        try container.encode(ruleID, forKey: .ruleID)
        try container.encodeIfPresent(groupName, forKey: .groupName)
        try container.encode(secondaryExposures, forKey: .secondaryExposures)
        try container.encode(evaluationDetails, forKey: .evaluationDetails)
        try container.encode(didPassRule, forKey: .didPassRule)
    }
}
