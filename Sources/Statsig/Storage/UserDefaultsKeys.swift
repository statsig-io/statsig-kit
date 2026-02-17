enum UserDefaultsKeys {
    static let localOverridesKey = "com.Statsig.InternalStore.localOverridesKey"
    static let localStorageKey = "com.Statsig.InternalStore.localStorageKeyV2"
    static let cacheKeyMappingKey = "com.Statsig.InternalStore.cacheKeyMappingKey"
    static let stickyDeviceExperimentsKey = "com.Statsig.InternalStore.stickyDeviceExperimentsKey"
    static let networkFallbackInfoKey = "com.Statsig.InternalStore.networkFallbackInfoKey"
    static let stableIDKey = "com.Statsig.InternalStore.stableIDKey"

    static let DEPRECATED_localStorageKey = "com.Statsig.InternalStore.localStorageKey"
    static let DEPRECATED_stickyUserExperimentsKey =
        "com.Statsig.InternalStore.stickyUserExperimentsKey"
    static let DEPRECATED_stickyUserIDKey = "com.Statsig.InternalStore.stickyUserIDKey"

    static func getFailedEventsStorageKey(_ sdkKey: String) -> String {
        return getFailedEventStorageKey(sdkKey)
    }
}

fileprivate let failedLogsKeyPrefix =
    "com.Statsig.EventLogger.loggingRequestUserDefaultsKey"

// TODO: delete after removing usage in Kong
internal func getFailedEventStorageKey(_ sdkKey: String) -> String {
    return "\(failedLogsKeyPrefix):\(sdkKey.djb2())"
}
