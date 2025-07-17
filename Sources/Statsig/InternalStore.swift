import Foundation

import CommonCrypto

fileprivate let MaxCachedUserObjects = 10

public struct StatsigOverrides {
    public var gates: [String: Bool]
    public var configs: [String: [String: Any]]
    public var params: [String: [String: Any]]

    init(_ overrides: [String: Any]) {
        gates = overrides[InternalStore.gatesKey] as? [String: Bool] ?? [:]
        configs = overrides[InternalStore.configsKey] as? [String: [String: Any]] ?? [:]
        params = overrides[InternalStore.paramStoresKey] as? [String: [String: Any]] ?? [:]
    }
}

public struct BootstrapMetadata {
    var generatorSDKInfo: [String: String]?
    var lcut: Int?
    var user: [String: Any]?
    
    func toDictionary() -> [String: Any] {
        var dict = [String: Any]()

        if let generatorSDKInfo = generatorSDKInfo {
            dict["generatorSDKInfo"] = generatorSDKInfo
        }

        if let lcut = lcut {
            dict["lcut"] = lcut
        }

        if let user = user {
            dict["user"] = user
        }

        return dict
    }
}

internal struct SDKFlags: Decodable {    
    var enableLogEventCompression: Bool = false

    init() {}

    init(from payload: Any?) {
        if let value = (payload as? [String : Any])?["enable_log_event_compression"] as? Bool {
            self.enableLogEventCompression = value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enableLogEventCompression = "enable_log_event_compression"
    }
}

struct StatsigValuesCache {
    var cacheByID: [String: [String: Any]]
    var userCacheKey: UserCacheKey
    var userLastUpdateTime: Double
    var stickyDeviceExperiments: [String: [String: Any]]
    var networkFallbackInfo: [String: [String: Any]]
    /*
     Maps .v2 cache keys to .full cache keys
     */
    var cacheKeyMapping: [String: String]
    var source: EvaluationSource = .Loading

    var lcut: UInt64? = nil
    var receivedValuesAt: UInt64? = nil
    var gates: [String: [String: Any]]? = nil
    var configs: [String: [String: Any]]? = nil
    var layers: [String: [String: Any]]? = nil
    var paramStores: [String: [String: Any]]? = nil
    var hashUsed: String? = nil
    var sdkKey: String
    var options: StatsigOptions
    var bootstrapMetadata: BootstrapMetadata? = nil
    var sdkFlags: SDKFlags?

    var userCache: [String: Any] {
        didSet {
            lcut = userCache[InternalStore.lcutKey] as? UInt64
            receivedValuesAt = userCache[InternalStore.evalTimeKey] as? UInt64
            gates = userCache[InternalStore.gatesKey] as? [String: [String: Any]]
            configs = userCache[InternalStore.configsKey] as? [String: [String: Any]]
            layers = userCache[InternalStore.layerConfigsKey] as? [String: [String: Any]]
            paramStores = userCache[InternalStore.paramStoresKey] as? [String: [String: Any]]
            hashUsed = userCache[InternalStore.hashUsedKey] as? String
            bootstrapMetadata = userCache[InternalStore.bootstrapMetadata] as? BootstrapMetadata
            sdkFlags = SDKFlags(from: userCache[InternalStore.sdkFlagsKey])
        }
    }

    init(_ sdkKey: String, _ user: StatsigUser, _ options: StatsigOptions) {
        self.options = options
        self.sdkKey = sdkKey
        self.cacheByID = StatsigValuesCache.loadDictMigratingIfRequired(forKey: InternalStore.localStorageKey)
        self.stickyDeviceExperiments = StatsigValuesCache.loadDictMigratingIfRequired(forKey: InternalStore.stickyDeviceExperimentsKey)
        self.networkFallbackInfo = StatsigValuesCache.loadDictMigratingIfRequired(forKey: InternalStore.networkFallbackInfoKey)
        self.cacheKeyMapping = StatsigUserDefaults.defaults.dictionarySafe(forKey: InternalStore.cacheKeyMappingKey) as? [String: String] ?? [:]

        self.userCache = [:]
        self.userCacheKey = UserCacheKey.from(options, user, sdkKey)
        self.userLastUpdateTime = 0

        self.setUserCacheKeyAndValues(user, withBootstrapValues: options.initializeValues)
        self.migrateLegacyStickyExperimentValues(user)
    }

    func getGate(_ gateName: String) -> FeatureGate {
        guard let gates = gates else {
            PrintHandler.log("[Statsig]: Failed to get feature gate with name \(gateName). Returning false as the default.")
            return createUnfoundGate(gateName)
        }

        if let gateObj = gates[gateName] ?? gates[gateName.hashSpecName(hashUsed)]{
            return FeatureGate(
                name: gateName,
                gateObj: gateObj,
                evalDetails: getEvaluationDetails(.Recognized)
            )
        }

        PrintHandler.log("[Statsig]: The feature gate with name \(gateName) does not exist. Returning false as the default.")
        return createUnfoundGate(gateName)
    }

    func getConfig(_ configName: String) -> DynamicConfig {
        guard let configs = configs else {
            PrintHandler.log("[Statsig]: Failed to get config with name \(configName). Returning a dummy DynamicConfig that will only return default values.")
            return createUnfoundDynamicConfig(configName)
        }

        if let configObj = configs[configName] ?? configs[configName.hashSpecName(hashUsed)] {
            return DynamicConfig(
                configName: configName,
                configObj: configObj,
                evalDetails: getEvaluationDetails(.Recognized))
        }

        PrintHandler.log("[Statsig]: \(configName) does not exist. Returning a dummy DynamicConfig that will only return default values.")
        return createUnfoundDynamicConfig(configName)
    }

    func getLayer(_ client: StatsigClient?, _ layerName: String) -> Layer {
        guard let layers = layers else {
            PrintHandler.log("[Statsig]: Failed to get layer with name \(layerName). Returning an empty Layer.")
            return createUnfoundLayer(client, layerName)
        }

        if let configObj = layers[layerName] ?? layers[layerName.hashSpecName(hashUsed)] {
            return Layer(
                client: client,
                name: layerName,
                configObj: configObj, 
                evalDetails: getEvaluationDetails(.Recognized)
            )
        }

        PrintHandler.log("[Statsig]: The layer with name \(layerName) does not exist. Returning an empty Layer.")
        return createUnfoundLayer(client, layerName)
    }
    
    func getParamStore(_ client: StatsigClient?, _ storeName: String) -> ParameterStore {
        guard let stores = paramStores else {
            PrintHandler.log("[Statsig]: Failed to get parameter store with name \(storeName). Returning an empty ParameterStore.")
            return createUnfoundParamStore(client, storeName)
        }

        if let config = stores[storeName] ?? stores[storeName.hashSpecName(hashUsed)] {
            return ParameterStore(
                name: storeName,
                evaluationDetails: getEvaluationDetails(.Recognized),
                client: client,
                configuration: config
            )
        }

        PrintHandler.log("[Statsig]: The parameter store with name \(storeName) does not exist. Returning an empty ParameterStore.")
        return createUnfoundParamStore(client, storeName)
    }

    func getStickyExperiment(_ expName: String) -> [String: Any]? {
        let expNameHash = expName.hashSpecName(hashUsed)
        if let stickyExps = userCache[InternalStore.stickyExpKey] as? [String: [String: Any]],
           let expObj = stickyExps[expNameHash] {
            return expObj
        } else if let expObj = stickyDeviceExperiments[expNameHash] {
            return expObj
        }
        return nil
    }

    func getNetworkFallbackInfo() -> FallbackInfo {
        var fallbackInfo: FallbackInfo = FallbackInfo()
        for (key, info) in self.networkFallbackInfo {
            if let endpoint = Endpoint(rawValue: key),
                let expiryTime = info["expiryTime"] as? TimeInterval,
                let previous = info["previous"] as? [String],
                let infoURL = info["url"] as? String,
                let url = URL(string: infoURL)
            {
                fallbackInfo[endpoint] = FallbackInfoEntry(url: url, previous: previous, expiryTime: Date(timeIntervalSince1970: expiryTime))
            }
        }
        return fallbackInfo
    }

    mutating func saveNetworkFallbackInfo(_ fallbackInfo: FallbackInfo?) {
        guard let fallbackInfo = fallbackInfo, !fallbackInfo.isEmpty else {
            StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.networkFallbackInfoKey)
            return;
        }

        var dict = [String: [String: Any]]()
        for (endpoint, entry) in fallbackInfo {
            dict[endpoint.rawValue] = [
                "url": entry.url.absoluteString,
                "expiryTime": entry.expiryTime.timeIntervalSince1970,
                "previous": entry.previous,
            ]
        }
        StatsigUserDefaults.defaults.setDictionarySafe(dict, forKey: InternalStore.networkFallbackInfoKey)
    }

    func getEvaluationDetails(_ reason: EvaluationReason? = nil) -> EvaluationDetails {
        EvaluationDetails(
            source: source,
            reason: reason,
            lcut: lcut,
            receivedAt: receivedValuesAt
        )
    }

    func getLastUpdatedTime(user: StatsigUser) -> UInt64 {
        if (userCache[InternalStore.userHashKey] as? String == user.getFullUserHash()) {
            let cachedValue = userCache[InternalStore.lcutKey]
            return cachedValue as? UInt64 ?? 0
        }

        return 0
    }
    
    func getBootstrapMetadata() -> BootstrapMetadata? {
        return userCache[InternalStore.bootstrapMetadata] as? BootstrapMetadata
    }

    func getPreviousDerivedFields(user: StatsigUser) -> [String: String] {
        if (userCache[InternalStore.userHashKey] as? String == user.getFullUserHash()) {
            return userCache[InternalStore.derivedFieldsKey] as? [String: String] ?? [:]
        }

        return [:]
    }

    func getFullChecksum(user: StatsigUser) -> String? {
        if (userCache[InternalStore.userHashKey] as? String == user.getFullUserHash()) {
            return userCache[InternalStore.fullChecksum] as? String ?? nil
        }

        return nil
    }

    func getSDKFlags(user: StatsigUser) -> SDKFlags {
        if userCache[InternalStore.userHashKey] as? String == user.getFullUserHash() {
            return sdkFlags ?? SDKFlags();
        }

        return SDKFlags()
    }

    mutating func updateUser(_ newUser: StatsigUser, _ values: [String: Any]? = nil) {
        // when updateUser is called, state will be uninitialized until updated values are fetched or local cache is retrieved
        source = .Loading
        setUserCacheKeyAndValues(newUser, withBootstrapValues: values)
    }

    mutating func saveValues(_ values: [String: Any], _ cacheKey: UserCacheKey, _ userHash: String?) {
        var cache = cacheKey.full == userCacheKey.full ? userCache : (getCacheValues(forCacheKey: cacheKey) ?? getDefaultValues())

        let hasUpdates = values["has_updates"] as? Bool == true
        if hasUpdates {
            cache[InternalStore.gatesKey] = values[InternalStore.gatesKey]
            cache[InternalStore.configsKey] = values[InternalStore.configsKey]
            cache[InternalStore.layerConfigsKey] = values[InternalStore.layerConfigsKey]
            cache[InternalStore.paramStoresKey] = values[InternalStore.paramStoresKey]
            cache[InternalStore.lcutKey] = Time.parse(values[InternalStore.lcutKey])
            cache[InternalStore.evalTimeKey] = Time.now()
            cache[InternalStore.userHashKey] = userHash
            cache[InternalStore.hashUsedKey] = values[InternalStore.hashUsedKey]
            cache[InternalStore.derivedFieldsKey] = values[InternalStore.derivedFieldsKey]
            cache[InternalStore.fullChecksum] = values[InternalStore.fullChecksum]
            cache[InternalStore.sdkFlagsKey] = values[InternalStore.sdkFlagsKey]
        }

        if (userCacheKey.full == cacheKey.full) {
            // Now the values we serve came from network request
            source = hasUpdates ? .Network : .NetworkNotModified
            userCache = cache
        }

        cacheByID[cacheKey.full] = cache
        cacheKeyMapping[userCacheKey.v2] = userCacheKey.full
        runCacheEviction()
    }

    mutating func runCacheEviction() {
        if (cacheByID.count <= MaxCachedUserObjects) {
            return
        }

        var oldestTime = UInt64.max
        var oldestEntryKey: String? = nil
        for (key, value) in cacheByID {
            let evalTime = Time.parse(value[InternalStore.evalTimeKey])
            if evalTime < oldestTime {
                oldestTime = evalTime
                oldestEntryKey = key
            }
        }

        if let key = oldestEntryKey {
            cacheByID.removeValue(forKey: key)
            cacheKeyMapping.removeValue(forKey: key)
            if let cacheKeyMappingIndex = cacheKeyMapping.firstIndex(where: { $1 == key }) {
                cacheKeyMapping.remove(at: cacheKeyMappingIndex)
            }
        }
    }

    mutating func saveStickyExperimentIfNeeded(_ expName: String, _ latestValue: ConfigProtocol) {
        let expNameHash = expName.hashSpecName(hashUsed)
        // If is IN this ACTIVE experiment, then we save the value as sticky
        if latestValue.isExperimentActive, latestValue.isUserInExperiment {
            if latestValue.isDeviceBased {
                stickyDeviceExperiments[expNameHash] = latestValue.rawValue
            } else {
                userCache[jsonDict: InternalStore.stickyExpKey]?[expNameHash] = latestValue.rawValue
            }
            saveToUserDefaults()
        }
    }

    mutating func removeStickyExperiment(_ expName: String) {
        let expNameHash = expName.hashSpecName(hashUsed)
        stickyDeviceExperiments.removeValue(forKey: expNameHash)
        userCache[jsonDict: InternalStore.stickyExpKey]?.removeValue(forKey: expNameHash)
        saveToUserDefaults()
    }

    private func getCacheValues(forCacheKey key: UserCacheKey) -> [String: Any]? {
        // Full User Hash Key
        if let fullHashCachedValues = cacheByID[key.full] {
            return fullHashCachedValues
        }

        // v2 Key
        if let v2KeyCachedValues = cacheByID[key.v2] ?? cacheByID[key.v1] {
            return v2KeyCachedValues
        }

        // Map v2 -> full cache
        if let cacheMappedKey = cacheKeyMapping[key.v2],
            let cachedValues = cacheByID[cacheMappedKey]  {
                return cachedValues
        }

        return nil;
    }

    private func getDefaultValues() -> [String: Any] {
        [
            InternalStore.gatesKey: [:],
            InternalStore.configsKey: [:],
            InternalStore.stickyExpKey: [:],
            "time": 0,
        ]
    }

    private mutating func saveToUserDefaults() {
        cacheByID[userCacheKey.full] = userCache
        StatsigUserDefaults.defaults.setDictionarySafe(cacheByID, forKey: InternalStore.localStorageKey)
        StatsigUserDefaults.defaults.setDictionarySafe(stickyDeviceExperiments, forKey: InternalStore.stickyDeviceExperimentsKey)
        StatsigUserDefaults.defaults.setDictionarySafe(networkFallbackInfo, forKey: InternalStore.networkFallbackInfoKey)
        StatsigUserDefaults.defaults.setDictionarySafe(cacheKeyMapping, forKey: InternalStore.cacheKeyMappingKey)
    }

    private mutating func setUserCacheKeyAndValues(
        _ user: StatsigUser,
        withBootstrapValues bootstrapValues: [String: Any]? = nil
    ) {
        userCacheKey = UserCacheKey.from(options, user, sdkKey)

        migrateOldUserCacheKey()

        // Bootstrap
        if let bootstrapValues = bootstrapValues {
            cacheByID[userCacheKey.full] = bootstrapValues
            cacheKeyMapping[userCacheKey.v2] = userCacheKey.full
            userCache = bootstrapValues
            let bootstrapMetadata = extractBootstrapMetadata(from: bootstrapValues)
            userCache[InternalStore.bootstrapMetadata] = bootstrapMetadata
            receivedValuesAt = Time.now()
            source = BootstrapValidator.isValid(user, bootstrapValues)
                ? .Bootstrap
                : .InvalidBootstrap
            
            return
        }

        // Cache
        if let cachedValues = getCacheValues(forCacheKey: userCacheKey) {
            source = .Cache
            userCache = cachedValues
            return
        }

        // Default values
        userCache = getDefaultValues()
    }
    
    private func extractBootstrapMetadata(from bootstrapValues: [String: Any]) -> BootstrapMetadata {
        var bootstrapMetadata = BootstrapMetadata()
        
        if let generatorSDKInfo = bootstrapValues["sdkInfo"] as? [String: String] {
            bootstrapMetadata.generatorSDKInfo = generatorSDKInfo
        }
        
        if let userMetadata = bootstrapValues["user"] as? [String: Any] {
            bootstrapMetadata.user = userMetadata
        }
        
        if let lcut = bootstrapValues["time"] as? Int {
            bootstrapMetadata.lcut = lcut
        }
        
        return bootstrapMetadata
    }

    private static func loadDictMigratingIfRequired(forKey key: String) -> [String: [String: Any]] {
        if let dict = StatsigUserDefaults.defaults.dictionarySafe(forKey: key) as? [String: [String: Any]] {
            return dict
        }

        // Load and Migrate Legacy
        if let dict = StatsigUserDefaults.defaults.dictionary(forKey: key) as? [String: [String: Any]] {
            StatsigUserDefaults.defaults.setDictionarySafe(dict, forKey: key)
            return dict
        }

        return [:]
    }

    private mutating func migrateLegacyStickyExperimentValues(_ currentUser: StatsigUser) {
        let previousUserID = StatsigUserDefaults.defaults.string(forKey: InternalStore.DEPRECATED_stickyUserIDKey) ?? ""
        let previousUserStickyExperiments = StatsigUserDefaults.defaults.dictionary(forKey: InternalStore.DEPRECATED_stickyUserExperimentsKey)
        if previousUserID == currentUser.userID, let oldStickyExps = previousUserStickyExperiments {
            userCache[InternalStore.stickyExpKey] = oldStickyExps
        }

        let previousCache = StatsigUserDefaults.defaults.dictionary(forKey: InternalStore.DEPRECATED_localStorageKey)
        if let previousCache = previousCache {
            if let gates = userCache[InternalStore.gatesKey] as? [String: Bool], gates.count == 0 {
                userCache[InternalStore.gatesKey] = previousCache[InternalStore.gatesKey]
            }
            if let configs = userCache[InternalStore.configsKey] as? [String: Any], configs.count == 0 {
                userCache[InternalStore.configsKey] = previousCache[InternalStore.configsKey]
            }
        }

        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.DEPRECATED_localStorageKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.DEPRECATED_stickyUserExperimentsKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.DEPRECATED_stickyUserIDKey)
    }

    private mutating func migrateOldUserCacheKey() {
        let v1Cache = cacheByID[userCacheKey.v1]
        let v2Cache = cacheByID[userCacheKey.v2]
        let oldCache = v2Cache ?? v1Cache

        if v1Cache != nil {
            cacheByID.removeValue(forKey: userCacheKey.v1)
        }
        if v2Cache != nil {
            cacheByID.removeValue(forKey: userCacheKey.v2)
        }

        if cacheByID[userCacheKey.full] == nil && oldCache != nil {
            cacheByID[userCacheKey.full] = oldCache
        }
    }

    private func createUnfoundGate(_ name: String) -> FeatureGate {
        FeatureGate(
            name: name,
            value: false,
            ruleID: "",
            evalDetails: getEvaluationDetails(.Unrecognized)
        )
    }

    private func createUnfoundDynamicConfig(_ name: String) -> DynamicConfig {
        DynamicConfig(
            configName: name,
            evalDetails: getEvaluationDetails(.Unrecognized)
        )
    }

    private func createUnfoundLayer(_ client: StatsigClient?, _ name: String) -> Layer {
        Layer(
            client: client,
            name: name,
            evalDetails: getEvaluationDetails(.Unrecognized)
        )
    }
    
    private func createUnfoundParamStore(_ client: StatsigClient?, _ name: String) -> ParameterStore {
        ParameterStore(name: name, evaluationDetails: getEvaluationDetails(.Unrecognized))
    }
    
    func getEvaluationSource() -> EvaluationSource {
        return source
    }
}

class InternalStore {
    static let localOverridesKey = "com.Statsig.InternalStore.localOverridesKey"
    static let localStorageKey = "com.Statsig.InternalStore.localStorageKeyV2"
    static let cacheKeyMappingKey = "com.Statsig.InternalStore.cacheKeyMappingKey"
    static let stickyDeviceExperimentsKey = "com.Statsig.InternalStore.stickyDeviceExperimentsKey"
    static let networkFallbackInfoKey = "com.Statsig.InternalStore.networkFallbackInfoKey"

    static let DEPRECATED_localStorageKey = "com.Statsig.InternalStore.localStorageKey"
    static let DEPRECATED_stickyUserExperimentsKey = "com.Statsig.InternalStore.stickyUserExperimentsKey"
    static let DEPRECATED_stickyUserIDKey = "com.Statsig.InternalStore.stickyUserIDKey"

    static let storeQueueLabel = "com.Statsig.storeQueue"

    static let gatesKey = "feature_gates"
    static let configsKey = "dynamic_configs"
    static let stickyExpKey = "sticky_experiments"
    static let layerConfigsKey = "layer_configs"
    static let paramStoresKey = "param_stores"
    static let lcutKey = "time"
    static let evalTimeKey = "evaluation_time"
    static let userHashKey = "user_hash"
    static let hashUsedKey = "hash_used"
    static let derivedFieldsKey = "derived_fields"
    static let bootstrapMetadata = "bootstrap_metadata"
    static let fullChecksum = "full_checksum"
    static let fullUserHashKey = "full_user_hash"
    static let sdkFlagsKey = "sdk_flags"

    var cache: StatsigValuesCache
    var localOverrides: [String: Any] = InternalStore.getEmptyOverrides()
    let storeQueue = DispatchQueue(label: storeQueueLabel, qos: .userInitiated, attributes: .concurrent)

    init(_ sdkKey: String, _ user: StatsigUser, options: StatsigOptions) {
        Diagnostics.mark?.initialize.readCache.start()
        cache = StatsigValuesCache(sdkKey, user, options)
        let savedOverrides = StatsigUserDefaults.defaults.dictionarySafe(forKey: InternalStore.localOverridesKey) ?? [:]
        localOverrides = InternalStore.getEmptyOverrides().merging(savedOverrides) { (_, saved) in saved }
        Diagnostics.mark?.initialize.readCache.end(success: true)
    }
    
    func getBootstrapMetadata() -> BootstrapMetadata? {
        storeQueue.sync {
            return cache.getBootstrapMetadata()
        }
    }

    func getNetworkFallbackInfo() -> FallbackInfo {
        storeQueue.sync {
            return cache.getNetworkFallbackInfo()
        }
    }

    func saveNetworkFallbackInfo(_ fallbackInfo: FallbackInfo?) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.cache.saveNetworkFallbackInfo(fallbackInfo)
        }
    }
    
    func getInitializationValues(user: StatsigUser) -> (lastUpdateTime: UInt64, previousDerivedFields: [String: String], fullChecksum: String?) {
        storeQueue.sync {
            return (
                lastUpdateTime: cache.getLastUpdatedTime(user: user),
                previousDerivedFields: cache.getPreviousDerivedFields(user: user),
                fullChecksum: cache.getFullChecksum(user: user)
            )
        }
    }

    func getSDKFlags(user: StatsigUser) -> SDKFlags {
        storeQueue.sync {
            return cache.getSDKFlags(user: user)
        }
    }

    func checkGate(forName: String) -> FeatureGate {
        storeQueue.sync {
            if let override = (localOverrides[InternalStore.gatesKey] as? [String: Bool])?[forName] {
                return FeatureGate(
                    name: forName,
                    value: override,
                    ruleID: "override",
                    evalDetails: cache.getEvaluationDetails(.LocalOverride)
                )
            }
            return cache.getGate(forName)
        }
    }

    func getConfig(forName: String) -> DynamicConfig {
        storeQueue.sync {
            if let override = (localOverrides[InternalStore.configsKey] as? [String: [String: Any]])?[forName] {
                return DynamicConfig(
                    configName: forName,
                    value: override,
                    ruleID: "override",
                    evalDetails: cache.getEvaluationDetails(.LocalOverride)
                )
            }
            return cache.getConfig(forName)
        }
    }

    func getExperiment(forName experimentName: String, keepDeviceValue: Bool) -> DynamicConfig {
        let latestValue = getConfig(forName: experimentName)
        return getPossiblyStickyValue(
            experimentName,
            latestValue: latestValue,
            keepDeviceValue: keepDeviceValue,
            isLayer: false,
            factory: { name, data in
                DynamicConfig(
                    name: name,
                    configObj: data,
                    evalDetails: cache.getEvaluationDetails(.Sticky)
                )
            })
    }

    func getLayer(client: StatsigClient?, forName layerName: String, keepDeviceValue: Bool) -> Layer {
        let latestValue: Layer = storeQueue.sync {
            if let override = (localOverrides[InternalStore.layerConfigsKey] as? [String: [String: Any]])?[layerName] {
                return Layer(
                    client: nil,
                    name: layerName,
                    value: override,
                    ruleID: "override",
                    groupName: nil,
                    evalDetails: cache.getEvaluationDetails(.LocalOverride)
                )
            }
            return cache.getLayer(client, layerName)
        }
        return getPossiblyStickyValue(
            layerName,
            latestValue: latestValue,
            keepDeviceValue: keepDeviceValue,
            isLayer: true,
            factory: { name, data in
                return Layer(
                    client: client,
                    name: name,
                    configObj: data,
                    evalDetails: cache.getEvaluationDetails(.Sticky)
                )
            })
    }
    
    func getParamStore(client: StatsigClient?, forName storeName: String) -> ParameterStore {
        storeQueue.sync {
            if let override = (localOverrides[InternalStore.paramStoresKey] as? [String: [String: Any]])?[storeName] {
                return ParameterStore(
                    name: storeName,
                    evaluationDetails: cache.getEvaluationDetails(.LocalOverride),
                    client: client,
                    configuration: override.mapValues {[
                        "ref_type": "static",
                        "param_type": getTypeOfValue($0) ?? "unknown",
                        "value": $0
                    ]}
                )
            }
            return cache.getParamStore(client, storeName)
        }
    }

    func finalizeValues(
        completionQueue: DispatchQueue = Thread.isMainThread ? .main : .global(),
        completion: (() -> Void)? = nil
    ) {
        storeQueue.async(flags: .barrier) { [weak self] in
            if self?.cache.source == .Loading {
                self?.cache.source = .NoValues
            }

            completionQueue.async {
                completion?()
            }
        }
    }

    func saveValues(
        _ values: [String: Any],
        _ cacheKey: UserCacheKey,
        _ userHash: String?,
        _ completion: (() -> Void)? = nil
    ) {
        guard SDKKeyValidator.validate(self.cache.sdkKey, values) else {
            completion?()
            return
        }

        storeQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.cache.saveValues(values, cacheKey, userHash)
            let cacheByID = self.cache.cacheByID
            let cacheKeyMapping = self.cache.cacheKeyMapping

            DispatchQueue.global().async() {
                StatsigUserDefaults.defaults.setDictionarySafe(cacheByID, forKey: InternalStore.localStorageKey)
                StatsigUserDefaults.defaults.setDictionarySafe(cacheKeyMapping, forKey: InternalStore.cacheKeyMappingKey)
            }

            DispatchQueue.global().async { completion?() }
        }
    }

    func updateUser(_ newUser: StatsigUser, values: [String: Any]? = nil) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.cache.updateUser(newUser, values)
        }
    }

    static func deleteAllLocalStorage() {
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.DEPRECATED_localStorageKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.localStorageKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.cacheKeyMappingKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.DEPRECATED_stickyUserExperimentsKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.stickyDeviceExperimentsKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.networkFallbackInfoKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.DEPRECATED_stickyUserIDKey)
        StatsigUserDefaults.defaults.removeObject(forKey: InternalStore.localOverridesKey)
        _ = StatsigUserDefaults.defaults.synchronize()
    }

    // Local overrides functions
    func overrideGate(_ gateName: String, _ value: Bool) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.localOverrides[jsonDict: InternalStore.gatesKey]?[gateName] = value
            self?.saveOverrides()
        }
    }

    func overrideConfig(_ configName: String, _ value: [String: Any]) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.localOverrides[jsonDict: InternalStore.configsKey]?[configName] = value
            self?.saveOverrides()
        }
    }

    func overrideLayer(_ layerName: String, _ value: [String: Any]) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.localOverrides[jsonDict: InternalStore.layerConfigsKey]?[layerName] = value
            self?.saveOverrides()
        }
    }

    func overrideParamStore(_ storeName: String, _ value: [String: Any]) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.localOverrides[jsonDict: InternalStore.paramStoresKey]?[storeName] = value
            self?.saveOverrides()
        }
    }

    func removeOverride(_ name: String) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.localOverrides[jsonDict: InternalStore.gatesKey]?.removeValue(forKey: name)
            self?.localOverrides[jsonDict: InternalStore.configsKey]?.removeValue(forKey: name)
            self?.localOverrides[jsonDict: InternalStore.layerConfigsKey]?.removeValue(forKey: name)
            self?.localOverrides[jsonDict: InternalStore.paramStoresKey]?.removeValue(forKey: name)
        }
    }

    func removeAllOverrides() {
        storeQueue.async(flags: .barrier) { [weak self] in
            guard let this = self else { return }
            this.localOverrides = InternalStore.getEmptyOverrides()
            this.saveOverrides()
        }
    }

    func getAllOverrides() -> StatsigOverrides {
        storeQueue.sync {
            StatsigOverrides(localOverrides)
        }
    }

    private func saveOverrides() {
        StatsigUserDefaults.defaults.setDictionarySafe(localOverrides, forKey: InternalStore.localOverridesKey)
    }

    private static func getEmptyOverrides() -> [String: Any] {
        return [
            InternalStore.gatesKey: [:],
            InternalStore.configsKey: [:],
            InternalStore.layerConfigsKey: [:],
            InternalStore.paramStoresKey: [:]
        ]
    }

    // Sticky Logic: https://gist.github.com/daniel-statsig/3d8dfc9bdee531cffc96901c1a06a402
    private func getPossiblyStickyValue<T: ConfigProtocol>(
        _ name: String,
        latestValue: T,
        keepDeviceValue: Bool,
        isLayer: Bool,
        factory: (_ name: String, _ data: [String: Any]) -> T) -> T {
            return storeQueue.sync {
                if (!keepDeviceValue) {
                    return latestValue
                }

                // If there is no sticky value, save latest as sticky and return latest.
                guard let stickyValue = cache.getStickyExperiment(name) else {
                    saveStickyExperimentIfNeededThreaded(name, latestValue)
                    return latestValue
                }

                // Get the latest config value. Layers require a lookup by allocated_experiment_name.
                var latestExperimentValue: ConfigProtocol? = nil
                if isLayer {
                    latestExperimentValue = cache.getConfig(stickyValue["allocated_experiment_name"] as? String ?? "")
                } else {
                    latestExperimentValue = latestValue
                }


                if (latestExperimentValue?.isExperimentActive == true) {
                    return factory(name, stickyValue)
                }

                if (latestValue.isExperimentActive == true) {
                    saveStickyExperimentIfNeededThreaded(name, latestValue)
                } else {
                    removeStickyExperimentThreaded(name)
                }

                return latestValue
            }
        }

    private func removeStickyExperimentThreaded(_ name: String) {
        storeQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeStickyExperiment(name)
        }
    }

    private func saveStickyExperimentIfNeededThreaded(_ name: String, _ config: ConfigProtocol?) {
        guard let config = config else {
            return
        }

        storeQueue.async(flags: .barrier) { [weak self] in
            self?.cache.saveStickyExperimentIfNeeded(name, config)
        }
    }
    
    func getEvaluationSource() -> EvaluationSource {
        storeQueue.sync {
            return cache.getEvaluationSource()
        }
    }
}

extension String {
    func hashSpecName(_ hashUsed: String?) -> String {
        if hashUsed == "none" {
            return self
        }

        if hashUsed == "djb2" {
            return self.djb2()
        }

        return self.sha256()
    }

    func sha256() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }

    func djb2() -> String {
        var hash: Int32 = 0
        for c in self.utf16 {
            hash = (hash << 5) &- hash &+ Int32(c)
            hash = hash & hash
        }

        return String(format: "%u", UInt32(bitPattern: hash))

    }
}

// https://stackoverflow.com/a/41543070
extension Dictionary {
    subscript(jsonDict key: Key) -> [String: Any]? {
        get {
            return self[key] as? [String: Any]
        }
        set {
            self[key] = newValue as? Value
        }
    }
}

