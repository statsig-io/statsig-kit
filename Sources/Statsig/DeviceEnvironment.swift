import Foundation

struct DeviceEnvironment {
    private static let instance = DeviceEnvironment()

    private let stableIDKey = "com.Statsig.InternalStore.stableIDKey"

    static internal let deviceOS = PlatformCompatibility.deviceInfo.os
    static internal let sdkType: String = "ios-client"
    static internal let sdkVersion: String = "1.53.10"

    let lock = NSLock()
    var sessionID: String? { UUID().uuidString }
    var systemVersion: String { PlatformCompatibility.deviceInfo.systemVersion }
    var systemName: String { PlatformCompatibility.deviceInfo.systemName }
    var language: String { Locale.preferredLanguages[0] }
    var locale: String { Locale.current.identifier }
    var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    var appIdentifier = Bundle.main.bundleIdentifier

    var deviceModel: String {
        if let simulatorModelIdentifier = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorModelIdentifier
        }
        var sysinfo = utsname()
        uname(&sysinfo)
        if let deviceModel = String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii) {
            return deviceModel.trimmingCharacters(in: .controlCharacters)
        } else {
            return PlatformCompatibility.deviceInfo.model
        }
    }

    private init() {
    }

    func getStableID(_ overrideStableID: String? = nil) -> String {
        if let overrideStableID = overrideStableID {
            StatsigUserDefaults.defaults.setValue(overrideStableID, forKey: stableIDKey)
            return overrideStableID
        }

        if let storedStableID = StatsigUserDefaults.defaults.string(forKey: stableIDKey), storedStableID != "" {
            return storedStableID
        }

        let newStableID = UUID().uuidString
        StatsigUserDefaults.defaults.setValue(newStableID, forKey: stableIDKey)
        return newStableID
    }

    static func get(_ overrideStableID: String? = nil) -> [String: String?] {
        return instance.get(overrideStableID)
    }
    
    static func getSDKMetadata(_ overrideStableID: String? = nil) -> [String: String?] {
        return instance.getSDKMetadata(overrideStableID)
    }

    static func explicitGet(_ overrideStableID: String? = nil) -> [String: String] {
        return instance.get(overrideStableID).mapValues { val in
            return val ?? ""
        }
    }
    
    private func getSDKMetadata(_ overrideStableID: String? = nil) -> [String: String?] {
        lock.lock()
        defer { lock.unlock() }
        
        return [
            "sdkType": DeviceEnvironment.sdkType,
            "sdkVersion": DeviceEnvironment.sdkVersion,
            "sessionID": sessionID,
            "stableID": getStableID(overrideStableID)
        ]
    }

    private func get(_ overrideStableID: String? = nil) -> [String: String?] {
        lock.lock()
        defer { lock.unlock() }

        return [
            "appIdentifier": appIdentifier,
            "appVersion": appVersion,
            "deviceModel": deviceModel,
            "deviceOS": DeviceEnvironment.deviceOS,
            "language": language,
            "locale": locale,
            "sdkType": DeviceEnvironment.sdkType,
            "sdkVersion": DeviceEnvironment.sdkVersion,
            "sessionID": sessionID,
            "stableID": getStableID(overrideStableID),
            "systemVersion": systemVersion,
            "systemName": systemName
        ]
    }

}
