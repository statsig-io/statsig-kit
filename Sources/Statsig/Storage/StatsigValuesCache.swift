import Foundation

fileprivate let MaxCachedUserObjects = 10

struct StatsigValuesCache {
    var cacheByID: [String: [String: Any]]
    var needsCacheMigration: Bool = false
    var userCacheKey: UserCacheKey
    var userLastUpdateTime: Double
    var stickyDeviceExperiments: [String: [String: Any]]
    var networkFallbackInfo: [String: [String: Any]]
    /*
     Maps .v2 cache keys to .fullUserWithSDKKey cache keys
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
    var sdkConfigs: SDKConfigs?

    let storageServiceLock = NSLock()
    var storageService: StorageService?
    internal mutating func getStorageService(
        migrationStatus: StorageServiceMigrationStatus = StorageServiceMigrationStatus
            .migrationStatus
    ) -> StorageService? {
        let storageService: StorageService? = storageServiceLock.withLock {
            guard migrationStatus != .legacy else {
                return nil
            }

            if let storageService = self.storageService {
                return storageService
            }

            // Some stores initialize before multi-file storage is enabled and keep `storageService`
            // as nil. If another SDK key flips the global migration state later in the same session,
            // we still need this store to start using file-backed storage.
            // TODO: Remove this lazy fallback once multi-file storage is fully rolled out.
            let storageService = StorageService.forSDKKey(
                sdkKey, storageProvider: options.storageProvider)
            self.storageService = storageService
            return storageService
        }
        return storageService
    }

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
            sdkConfigs = SDKConfigs(from: userCache[InternalStore.sdkConfigsKey])
        }
    }

    init(
        _ sdkKey: String,
        _ user: StatsigUser,
        _ storageService: StorageService?,
        _ options: StatsigOptions
    ) {
        self.options = options
        self.sdkKey = sdkKey
        self.storageService = storageService
        self.userCacheKey = UserCacheKey.from(options, user, sdkKey)
        if let storageService = storageService {
            let loaded = StatsigValuesCache.loadCache(userCacheKey, storageService)
            self.cacheByID = loaded.cache
            self.cacheKeyMapping = [:]
            if loaded.needsMigration {
                StorageServiceMigrationStatus.setNeedsMigration()
            }
        } else {
            self.cacheByID = StatsigValuesCache.loadDictMigratingIfRequired(
                forKey: UserDefaultsKeys.localStorageKey)
            self.cacheKeyMapping =
                StatsigUserDefaults.defaults.dictionarySafe(
                    forKey: UserDefaultsKeys.cacheKeyMappingKey)
                as? [String: String] ?? [:]
        }
        self.stickyDeviceExperiments = StatsigValuesCache.loadDictMigratingIfRequired(
            forKey: UserDefaultsKeys.stickyDeviceExperimentsKey)
        self.networkFallbackInfo = StatsigValuesCache.loadDictMigratingIfRequired(
            forKey: UserDefaultsKeys.networkFallbackInfoKey)

        self.userCache = [:]
        self.userLastUpdateTime = 0

        self.setUserCacheKeyAndValues(user, withBootstrapValues: options.initializeValues)
        self.migrateLegacyStickyExperimentValues(user)
    }

    static func loadCache(
        _ userCacheKey: UserCacheKey,
        _ storageService: StorageService
    ) -> (cache: [String: [String: Any]], needsMigration: Bool) {
        let migrationStatus = StorageServiceMigrationStatus.migrationStatus
        if migrationStatus != .legacy {
            if let storageServicePayload = storageService.userPayload.read(
                key: userCacheKey)
            {
                return ([userCacheKey.fullUserWithSDKKey: storageServicePayload], false)
            }

            // If fully migrated, skip reading from UserDefaults
            if migrationStatus == .multiFile {
                return ([:], false)
            }
        }

        let userDefaultsDict = StatsigValuesCache.loadDictMigratingIfRequired(
            forKey: UserDefaultsKeys.localStorageKey)

        return (userDefaultsDict, !userDefaultsDict.isEmpty)
    }

    func getGate(_ gateName: String) -> FeatureGate {
        guard let gates = gates else {
            PrintHandler.log(
                "[Statsig]: Failed to get feature gate with name \(gateName). Returning false as the default."
            )
            return createUnfoundGate(gateName)
        }

        if let gateObj = gates[gateName] ?? gates[gateName.hashSpecName(hashUsed)] {
            return FeatureGate(
                name: gateName,
                gateObj: gateObj,
                evalDetails: getEvaluationDetails(.Recognized)
            )
        }

        PrintHandler.log(
            "[Statsig]: The feature gate with name \(gateName) does not exist. Returning false as the default."
        )
        return createUnfoundGate(gateName)
    }

    func getConfig(_ configName: String) -> DynamicConfig {
        guard let configs = configs else {
            PrintHandler.log(
                "[Statsig]: Failed to get config with name \(configName). Returning a dummy DynamicConfig that will only return default values."
            )
            return createUnfoundDynamicConfig(configName)
        }

        if let configObj = configs[configName] ?? configs[configName.hashSpecName(hashUsed)] {
            return DynamicConfig(
                configName: configName,
                configObj: configObj,
                evalDetails: getEvaluationDetails(.Recognized))
        }

        PrintHandler.log(
            "[Statsig]: \(configName) does not exist. Returning a dummy DynamicConfig that will only return default values."
        )
        return createUnfoundDynamicConfig(configName)
    }

    func getLayer(_ client: StatsigClient?, _ layerName: String) -> Layer {
        guard let layers = layers else {
            PrintHandler.log(
                "[Statsig]: Failed to get layer with name \(layerName). Returning an empty Layer.")
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

        PrintHandler.log(
            "[Statsig]: The layer with name \(layerName) does not exist. Returning an empty Layer.")
        return createUnfoundLayer(client, layerName)
    }

    func getParamStore(_ client: StatsigClient?, _ storeName: String) -> ParameterStore {
        guard let stores = paramStores else {
            PrintHandler.log(
                "[Statsig]: Failed to get parameter store with name \(storeName). Returning an empty ParameterStore."
            )
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

        PrintHandler.log(
            "[Statsig]: The parameter store with name \(storeName) does not exist. Returning an empty ParameterStore."
        )
        return createUnfoundParamStore(client, storeName)
    }

    func getStickyExperiment(_ expName: String) -> [String: Any]? {
        let expNameHash = expName.hashSpecName(hashUsed)
        if let stickyExps = userCache[InternalStore.stickyExpKey] as? [String: [String: Any]],
            let expObj = stickyExps[expNameHash]
        {
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
                fallbackInfo[endpoint] = FallbackInfoEntry(
                    url: url, previous: previous,
                    expiryTime: Date(timeIntervalSince1970: expiryTime))
            }
        }
        return fallbackInfo
    }

    mutating func saveNetworkFallbackInfo(_ fallbackInfo: FallbackInfo?) {
        guard let fallbackInfo = fallbackInfo, !fallbackInfo.isEmpty else {
            StatsigUserDefaults.defaults.removeObject(
                forKey: UserDefaultsKeys.networkFallbackInfoKey)
            return
        }

        var dict = [String: [String: Any]]()
        for (endpoint, entry) in fallbackInfo {
            dict[endpoint.rawValue] = [
                "url": entry.url.absoluteString,
                "expiryTime": entry.expiryTime.timeIntervalSince1970,
                "previous": entry.previous,
            ]
        }
        StatsigUserDefaults.defaults.setDictionarySafe(
            dict, forKey: UserDefaultsKeys.networkFallbackInfoKey)
    }

    func getEvaluationDetails(_ reason: EvaluationReason? = nil) -> EvaluationDetails {
        EvaluationDetails(
            source: source,
            reason: reason,
            lcut: lcut,
            receivedAt: receivedValuesAt
        )
    }

    func getInitializeResponseValues() -> [String: Any?] {
        [
            InternalStore.gatesKey: gates,
            InternalStore.configsKey: configs,
            InternalStore.layerConfigsKey: layers,
            InternalStore.paramStoresKey: paramStores,
            InternalStore.hashUsedKey: hashUsed,
            InternalStore.lcutKey: userCache[InternalStore.lcutKey],
            InternalStore.derivedFieldsKey: userCache[InternalStore.derivedFieldsKey],
            InternalStore.fullChecksum: userCache[InternalStore.fullChecksum],
            InternalStore.sdkFlagsKey: userCache[InternalStore.sdkFlagsKey],
            InternalStore.sdkConfigsKey: userCache[InternalStore.sdkConfigsKey],
            "has_updates": true,
        ]
    }

    func getLastUpdatedTime(user: StatsigUser) -> UInt64 {
        if userCache[InternalStore.userHashKey] as? String == user.getFullUserHash() {
            let cachedValue = userCache[InternalStore.lcutKey]
            return cachedValue as? UInt64 ?? 0
        }

        return 0
    }

    func getBootstrapMetadata() -> BootstrapMetadata? {
        return userCache[InternalStore.bootstrapMetadata] as? BootstrapMetadata
    }

    func getPreviousDerivedFields(user: StatsigUser) -> [String: String] {
        if userCache[InternalStore.userHashKey] as? String == user.getFullUserHash() {
            return userCache[InternalStore.derivedFieldsKey] as? [String: String] ?? [:]
        }

        return [:]
    }

    func getFullChecksum(user: StatsigUser) -> String? {
        if userCache[InternalStore.userHashKey] as? String == user.getFullUserHash() {
            return userCache[InternalStore.fullChecksum] as? String ?? nil
        }

        return nil
    }

    func getSDKFlags(user: StatsigUser) -> SDKFlags {
        if userCache[InternalStore.userHashKey] as? String == user.getFullUserHash() {
            return sdkFlags ?? SDKFlags()
        }

        return SDKFlags()
    }

    func getSDKConfigs(user: StatsigUser) -> SDKConfigs {
        if userCache[InternalStore.userHashKey] as? String == user.getFullUserHash() {
            return sdkConfigs ?? SDKConfigs()
        }

        return SDKConfigs()
    }

    mutating func updateUser(_ newUser: StatsigUser, _ values: [String: Any]? = nil) {
        // when updateUser is called, state will be uninitialized until updated values are fetched or local cache is retrieved
        source = .Loading
        setUserCacheKeyAndValues(newUser, withBootstrapValues: values)
    }

    mutating func saveValues(_ values: [String: Any], _ cacheKey: UserCacheKey, _ userHash: String?)
    {
        var cache =
            cacheKey.fullUserWithSDKKey == userCacheKey.fullUserWithSDKKey
            ? userCache : (getCacheValues(forCacheKey: cacheKey) ?? getDefaultValues())

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
            cache[InternalStore.sdkConfigsKey] = values[InternalStore.sdkConfigsKey]
        }

        if userCacheKey.fullUserWithSDKKey == cacheKey.fullUserWithSDKKey {
            // Now the values we serve came from network request
            source = hasUpdates ? .Network : .NetworkNotModified
            userCache = cache
        }

        cacheByID[cacheKey.fullUserWithSDKKey] = cache
        if StorageServiceMigrationStatus.migrationStatus == .legacy {
            cacheKeyMapping[userCacheKey.v2] = userCacheKey.fullUserWithSDKKey

            runCacheEviction()
        }

        persist(cacheKey, cache)
    }

    mutating func persist(_ cacheKey: UserCacheKey, _ payload: [String: Any]) {
        if let storageService = getStorageService() {
            storageService.userPayload.write(key: cacheKey, payload: payload)
            return
        }

        StatsigUserDefaults.defaults.setDictionarySafe(
            cacheByID, forKey: UserDefaultsKeys.localStorageKey)
        StatsigUserDefaults.defaults.setDictionarySafe(
            cacheKeyMapping, forKey: UserDefaultsKeys.cacheKeyMappingKey)
    }

    mutating func runCacheEviction() {
        if cacheByID.count <= MaxCachedUserObjects {
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

    private mutating func getCacheValues(forCacheKey key: UserCacheKey) -> [String: Any]? {
        // Cached Full User Hash Key
        if let fullHashCachedValues = cacheByID[key.fullUserWithSDKKey] {
            return fullHashCachedValues
        }

        let migrationStatus = StorageServiceMigrationStatus.migrationStatus
        let storageService = getStorageService(migrationStatus: migrationStatus)

        // Read from new storage
        if let storageService = storageService,
            let payload = storageService.userPayload.read(key: key, legacyMemoryCache: cacheByID)
        {
            cacheByID[key.fullUserWithSDKKey] = payload
            return payload
        }

        // Fallback to legacy if migration didn't complete yet
        guard migrationStatus != .multiFile else {
            return nil
        }

        // Legacy cached mappedFullUserHash (v2 -> full user hash)
        if migrationStatus != .multiFile,
            let cacheMappedKey = cacheKeyMapping[key.v2],
            let cachedValues = cacheByID[cacheMappedKey]
        {
            return cachedValues
        }

        // Legacy Keys from memory (v2 or v1)
        if migrationStatus != .multiFile,
            let v2KeyCachedValues = cacheByID[key.v2] ?? cacheByID[key.v1]
        {
            return v2KeyCachedValues
        }

        return nil
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
        cacheByID[userCacheKey.fullUserWithSDKKey] = userCache
        if let storageService = getStorageService() {
            storageService.userPayload.write(key: userCacheKey, payload: userCache)
        } else {
            StatsigUserDefaults.defaults.setDictionarySafe(
                cacheByID, forKey: UserDefaultsKeys.localStorageKey)
            StatsigUserDefaults.defaults.setDictionarySafe(
                cacheKeyMapping, forKey: UserDefaultsKeys.cacheKeyMappingKey)
        }
        StatsigUserDefaults.defaults.setDictionarySafe(
            stickyDeviceExperiments, forKey: UserDefaultsKeys.stickyDeviceExperimentsKey)
        StatsigUserDefaults.defaults.setDictionarySafe(
            networkFallbackInfo, forKey: UserDefaultsKeys.networkFallbackInfoKey)
    }

    private mutating func setUserCacheKeyAndValues(
        _ user: StatsigUser,
        withBootstrapValues bootstrapValues: [String: Any]? = nil
    ) {
        userCacheKey = UserCacheKey.from(options, user, sdkKey)

        migrateOldUserCacheKey()

        // Bootstrap
        if let bootstrapValues = bootstrapValues {
            cacheByID[userCacheKey.fullUserWithSDKKey] = bootstrapValues
            if StorageServiceMigrationStatus.migrationStatus == .legacy {
                cacheKeyMapping[userCacheKey.v2] = userCacheKey.fullUserWithSDKKey
            }
            userCache = bootstrapValues
            let bootstrapMetadata = extractBootstrapMetadata(from: bootstrapValues)
            userCache[InternalStore.bootstrapMetadata] = bootstrapMetadata
            receivedValuesAt = Time.now()
            source =
                BootstrapValidator.isValid(user, bootstrapValues)
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

    private func extractBootstrapMetadata(from bootstrapValues: [String: Any]) -> BootstrapMetadata
    {
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
        if let dict = StatsigUserDefaults.defaults.dictionarySafe(forKey: key)
            as? [String: [String: Any]]
        {
            return dict
        }

        // Load and Migrate Legacy
        if let dict = StatsigUserDefaults.defaults.dictionary(forKey: key)
            as? [String: [String: Any]]
        {
            StatsigUserDefaults.defaults.setDictionarySafe(dict, forKey: key)
            return dict
        }

        return [:]
    }

    private mutating func migrateLegacyStickyExperimentValues(_ currentUser: StatsigUser) {
        let previousUserID =
            StatsigUserDefaults.defaults.string(forKey: UserDefaultsKeys.DEPRECATED_stickyUserIDKey)
            ?? ""
        let previousUserStickyExperiments = StatsigUserDefaults.defaults.dictionary(
            forKey: UserDefaultsKeys.DEPRECATED_stickyUserExperimentsKey)
        if previousUserID == currentUser.userID, let oldStickyExps = previousUserStickyExperiments {
            userCache[InternalStore.stickyExpKey] = oldStickyExps
        }

        let previousCache = StatsigUserDefaults.defaults.dictionary(
            forKey: UserDefaultsKeys.DEPRECATED_localStorageKey)
        if let previousCache = previousCache {
            if let gates = userCache[InternalStore.gatesKey] as? [String: Bool], gates.count == 0 {
                userCache[InternalStore.gatesKey] = previousCache[InternalStore.gatesKey]
            }
            if let configs = userCache[InternalStore.configsKey] as? [String: Any],
                configs.count == 0
            {
                userCache[InternalStore.configsKey] = previousCache[InternalStore.configsKey]
            }
        }

        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.DEPRECATED_localStorageKey)
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.DEPRECATED_stickyUserExperimentsKey)
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.DEPRECATED_stickyUserIDKey)
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

        if cacheByID[userCacheKey.fullUserWithSDKKey] == nil && oldCache != nil {
            cacheByID[userCacheKey.fullUserWithSDKKey] = oldCache
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

    private func createUnfoundParamStore(_ client: StatsigClient?, _ name: String) -> ParameterStore
    {
        ParameterStore(name: name, evaluationDetails: getEvaluationDetails(.Unrecognized))
    }

    func getEvaluationSource() -> EvaluationSource {
        return source
    }
}
