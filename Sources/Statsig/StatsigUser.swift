import Foundation

/**
 The user object to be evaluated against your Statsig configurations (gates/experiments/dynamic configs).
 */
public struct StatsigUser: Sendable {
    /**
     An identifier for this user. Evaluated against the [User ID](https://docs.statsig.com/feature-gates/conditions#userid) criteria.
     */
    public let userID: String?

    /**
     An email address for this user. Evaluated against the [Email](https://docs.statsig.com/feature-gates/conditions#email) criteria.
     */
    public let email: String?

    /**
     An IP address associated with this user. Evaluated against the [IP Address](https://docs.statsig.com/feature-gates/conditions#ip) criteria.
     */
    public let ip: String?

    /**
     The country code associated with this user (e.g New Zealand => NZ). Evaluated against the [Country](https://docs.statsig.com/feature-gates/conditions#country) criteria.
     */
    public let country: String?

    /**
     An locale for this user.
     */
    public let locale: String?

    /**
     The current app version the user is interacting with. Evaluated against the [App Version](https://docs.statsig.com/feature-gates/conditions#app-version) criteria.
     */
    public let appVersion: String?

    /**
     Any custom fields for this user. Evaluated against the [Custom](https://docs.statsig.com/feature-gates/conditions#custom) criteria.
     */
    public let custom: [String: StatsigUserCustomTypeConvertible]?

    /**
     Any value you wish to use in evaluation, but not have logged with events can be stored in this field.
     */
    public let privateAttributes: [String: StatsigUserCustomTypeConvertible]?

    /**
     Controls whether non-SDK-type SDK version metadata should be excluded or included.
     Setting this option to `true` will exclude metadata related to non-SDK-type SDK versions. By default, this option is set to `false`, meaning all metadata is included.
     */
    public var optOutNonSdkMetadata: Bool?

    /**
     Any Custom IDs to associated with the user.

     See Also [Experiments With Custom ID Types](https://docs.statsig.com/guides/experiment-on-custom-id-types)
     */
    public let customIDs: [String: String]?

    /**
     This user's UserAgent
     */
    public var userAgent: String?

    var statsigEnvironment: [String: String] = [:]
    var deviceEnvironment: [String: String?]

    public init(
        userID: String? = nil,
        email: String? = nil,
        ip: String? = nil,
        country: String? = nil,
        locale: String? = nil,
        appVersion: String? = nil,
        custom: [String: StatsigUserCustomTypeConvertible]? = nil,
        privateAttributes: [String: StatsigUserCustomTypeConvertible]? = nil,
        optOutNonSdkMetadata: Bool? = false,
        customIDs: [String: String]? = nil,
        userAgent: String? = nil
    ) {
        self.userID = userID
        self.email = email
        self.ip = ip
        self.country = country
        self.locale = locale
        self.appVersion = appVersion
        self.customIDs = customIDs
        self.optOutNonSdkMetadata = optOutNonSdkMetadata
        self.userAgent = userAgent

        if let custom = custom, JSONSerialization.isValidJSONObject(custom) {
            self.custom = custom
        } else {
            if custom != nil {
                PrintHandler.log(
                    "[Statsig]: The provided custom value is not added to the user because it is not a valid JSON object."
                )
            }
            self.custom = nil
        }

        if let privateAttributes = privateAttributes,
            JSONSerialization.isValidJSONObject(privateAttributes)
        {
            self.privateAttributes = privateAttributes
        } else {
            if privateAttributes != nil {
                PrintHandler.log(
                    "[Statsig]: The provided privateAttributes is not added to the user because it is not a valid JSON object."
                )
            }
            self.privateAttributes = nil
        }

        if self.optOutNonSdkMetadata ?? false {
            self.deviceEnvironment = DeviceEnvironment.getSDKMetadata()
        } else {
            self.deviceEnvironment = DeviceEnvironment.get()
        }
    }

    mutating func setStableID(_ overrideStableID: String) {
        if self.optOutNonSdkMetadata ?? false {
            self.deviceEnvironment = DeviceEnvironment.getSDKMetadata(overrideStableID)
        } else {
            self.deviceEnvironment = DeviceEnvironment.get(overrideStableID)
        }
    }

    func toDictionary(forLogging: Bool) -> [String: Any?] {
        var dict = [String: Any?]()
        dict["userID"] = self.userID
        dict["email"] = self.email
        dict["ip"] = self.ip
        dict["country"] = self.country
        dict["userAgent"] = self.userAgent
        dict["locale"] = self.locale
        dict["appVersion"] = self.appVersion
        dict["custom"] = self.custom
        dict["statsigEnvironment"] = self.statsigEnvironment
        dict["customIDs"] = self.customIDs

        if !forLogging {
            dict["privateAttributes"] = self.privateAttributes
        }

        return dict
    }

    func getFullUserHash() -> String {
        let dict = toDictionary(forLogging: false)
        let sorted = getSortedPairsString(dict)
        return sorted.djb2()
    }
}

fileprivate func getSortedPairsString(_ dictionary: [String: Any?]) -> String {
    let sortedPairs = dictionary.sorted { $0.key < $1.key }
    var sortedResult = [String]()

    for (key, value) in sortedPairs {
        if let nestedDictionary = value as? [String: Any?] {
            let sortedNested = getSortedPairsString(nestedDictionary)
            sortedResult.append("\(key):\(sortedNested)")
        } else {
            sortedResult.append("\(key):\(value ?? "")")
        }
    }

    return sortedResult.joined(separator: ",")
}

extension StatsigUser {
    internal func getUnitID(_ type: String) -> String? {
        let lowered = type.lowercased()

        if lowered == "userid" {
            return self.userID
        }

        return self.customIDs?[type] ?? self.customIDs?[lowered]
    }

    static func empty() -> StatsigUser {
        StatsigUser(userID: "")
    }

    internal func getFromEnvironment(_ field: String?) -> JsonValue? {
        guard let field else {
            return nil
        }

        let lowered = field.lowercased()
        if let value = getEnvironmentValueString(lowered) {
            return .string(value)
        }

        return nil
    }

    internal func getUserValue(_ field: String?) -> JsonValue? {
        guard let field else {
            return nil
        }

        let lowered = field.lowercased()
        if let strValue = getUserValueString(lowered) {
            return .string(strValue)
        }

        if let value = self.custom?[field] ?? self.custom?[lowered],
            let jsonValue = JsonValue(value)
        {
            return jsonValue
        }

        if let value = self.privateAttributes?[field] ?? self.privateAttributes?[lowered],
            let jsonValue = JsonValue(value)
        {
            return jsonValue
        }

        return nil
    }

    private func getUserValueString(_ field: String) -> String? {
        switch field {
        case "userid", "user_id": return self.userID
        case "email": return self.email
        case "ip": return self.ip
        case "useragent", "user_agent": return self.userAgent
        case "country": return self.country
        case "locale": return self.locale
        case "appversion", "app_version": return self.appVersion
        default: return nil
        }
    }

    private func getEnvironmentValueString(_ field: String) -> String? {
        switch field {
        case "tier":
            return self.statsigEnvironment["tier"] ?? self.deviceEnvironment["tier"] as? String
        default: return nil
        }
    }
}
