
/**
 Typed bundle of StatsigMetadata for external consumption.
 */
public struct StatsigMetadata {
    var stableID: String? = nil
    var sdkType: String? = nil
    var sdkVersion: String? = nil
    var sessionID: String? = nil
    var appIdentifier: String? = nil
    var appVersion: String? = nil
    var deviceModel: String? = nil
    var deviceOS: String? = nil
    var locale: String? = nil
    var language: String? = nil
    var systemVersion: String? = nil
    var systemName: String? = nil
    
    internal static func buildMetadataFromEnvironmentDict(deviceEnvironment: [String: String?]) -> StatsigMetadata {
        return StatsigMetadata(
            stableID: deviceEnvironment[STABLE_ID_KEY] as? String,
            sdkType: deviceEnvironment[SDK_TYPE_KEY] as? String,
            sdkVersion: deviceEnvironment[SDK_VERSION_KEY] as? String,
            sessionID: deviceEnvironment[SESSION_ID_KEY] as? String,
            appIdentifier: deviceEnvironment[APP_IDENTIFIER_KEY] as? String,
            appVersion: deviceEnvironment[APP_VERSION_KEY] as? String,
            deviceModel: deviceEnvironment[DEVICE_MODEL_KEY] as? String,
            deviceOS: deviceEnvironment[DEVICE_OS_KEY] as? String,
            locale: deviceEnvironment[LOCALE_KEY] as? String,
            language: deviceEnvironment[LANGUAGE_KEY] as? String,
            systemVersion: deviceEnvironment[SYS_VERSION_KEY] as? String,
            systemName: deviceEnvironment[SYS_NAME_KEY] as? String
        )
    }
    
    internal static let STABLE_ID_KEY = "stableID"
    internal static let SDK_TYPE_KEY = "sdkType"
    internal static let SDK_VERSION_KEY = "sdkVersion"
    internal static let SESSION_ID_KEY = "sessionID"
    internal static let APP_IDENTIFIER_KEY = "appIdentifier"
    internal static let APP_VERSION_KEY = "appVersion"
    internal static let DEVICE_MODEL_KEY = "deviceModel"
    internal static let DEVICE_OS_KEY = "deviceOS"
    internal static let LOCALE_KEY = "locale"
    internal static let LANGUAGE_KEY = "language"
    internal static let SYS_VERSION_KEY = "systemVersion"
    internal static let SYS_NAME_KEY = "systemName"
}



