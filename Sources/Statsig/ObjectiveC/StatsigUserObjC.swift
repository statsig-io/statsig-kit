import Foundation

@objc(StatsigUser)
public final class StatsigUserObjC: NSObject {
    var user: StatsigUser

    @objc override public init() {
        self.user = StatsigUser()
    }

    @objc public init(userID: String) {
        self.user = StatsigUser(userID: userID)
    }

    @objc public init(customIDs: [String: String]) {
        self.user = StatsigUser(customIDs: customIDs)

    }

    @objc public convenience init(
        userID: String? = nil,
        email: String? = nil,
        ip: String? = nil,
        country: String? = nil,
        locale: String? = nil,
        appVersion: String? = nil,
        custom: [String: Any]? = nil,
        privateAttributes: [String: Any]? = nil
    ) {
        self.init(
            userID: userID,
            email: email,
            ip: ip,
            country: country,
            locale: locale,
            appVersion: appVersion,
            custom: custom,
            privateAttributes: privateAttributes,
            customIDs: nil,
            userAgent: nil)
    }

    @objc public convenience init(
        userID: String? = nil,
        email: String? = nil,
        ip: String? = nil,
        country: String? = nil,
        locale: String? = nil,
        appVersion: String? = nil,
        custom: [String: Any]? = nil,
        privateAttributes: [String: Any]? = nil,
        customIDs: [String: String]? = nil
    ) {
        self.init(
            userID: userID,
            email: email,
            ip: ip,
            country: country,
            locale: locale,
            appVersion: appVersion,
            custom: custom,
            privateAttributes: privateAttributes,
            customIDs: nil,
            userAgent: nil)
    }

    @objc public init(
        userID: String? = nil,
        email: String? = nil,
        ip: String? = nil,
        country: String? = nil,
        locale: String? = nil,
        appVersion: String? = nil,
        custom: [String: Any]? = nil,
        privateAttributes: [String: Any]? = nil,
        customIDs: [String: String]? = nil,
        userAgent: String? = nil
    ) {
        var filteredCustom = [String: StatsigUserCustomTypeConvertible]()
        if let custom = custom {
            custom.forEach { key, value in
                if let v = convertToUserCustomType(value) {
                    filteredCustom[key] = v
                } else {
                    PrintHandler.log(
                        "[Statsig]: the entry for key \(key) is dropped because it is not of a supported type."
                    )
                }
            }
        }

        var filteredPrivateAttributes = [String: StatsigUserCustomTypeConvertible]()
        if let privateAttributes = privateAttributes {
            privateAttributes.forEach { key, value in
                if let v = convertToUserCustomType(value) {
                    filteredPrivateAttributes[key] = v
                } else {
                    PrintHandler.log(
                        "[Statsig]: the entry for key \(key) is dropped because it is not of a supported type."
                    )
                }
            }
        }

        self.user = StatsigUser(
            userID: userID,
            email: email,
            ip: ip,
            country: country,
            locale: locale,
            appVersion: appVersion,
            custom: filteredCustom.isEmpty ? nil : filteredCustom,
            privateAttributes: filteredPrivateAttributes.isEmpty ? nil : filteredPrivateAttributes,
            customIDs: customIDs,
            userAgent: userAgent)
    }

    @objc public func getUserID() -> String? {
        return user.userID
    }

    @objc public func getCustomIDs() -> NSDictionary? {
        guard let dict = user.customIDs else {
            return nil
        }

        let result = NSMutableDictionary()

        for (key, value) in dict {
            result[key] = value
        }

        return result
    }

    @objc public func toDictionary() -> NSDictionary {
        let dict = user.toDictionary(forLogging: false)
        let result = NSMutableDictionary()

        for (key, value) in dict {
            if let value = value {
                result[key] = value
            }
        }

        return result
    }
}
