import CommonCrypto
import Foundation

public struct StatsigOverrides {
    public var gates: [String: Bool]
    public var configs: [String: [String: Any]]
    public var layers: [String: [String: Any]]
    public var params: [String: [String: Any]]

    init(_ overrides: [String: Any]) {
        gates = overrides[InternalStore.gatesKey] as? [String: Bool] ?? [:]
        configs = overrides[InternalStore.configsKey] as? [String: [String: Any]] ?? [:]
        layers = overrides[InternalStore.layerConfigsKey] as? [String: [String: Any]] ?? [:]
        params = overrides[InternalStore.paramStoresKey] as? [String: [String: Any]] ?? [:]
    }
}

class InternalStore {
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
    let storeQueue = DispatchQueue(
        label: storeQueueLabel, qos: .userInitiated, attributes: .concurrent)

    init(_ sdkKey: String, _ user: StatsigUser, options: StatsigOptions) {
        Diagnostics.mark?.initialize.readCache.start()
        cache = StatsigValuesCache(sdkKey, user, options)
        let savedOverrides =
            StatsigUserDefaults.defaults.dictionarySafe(forKey: UserDefaultsKeys.localOverridesKey)
            ?? [:]
        localOverrides = InternalStore.getEmptyOverrides().merging(savedOverrides) { (_, saved) in
            saved
        }
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

    func getInitializationValues(user: StatsigUser) -> (
        lastUpdateTime: UInt64, previousDerivedFields: [String: String], fullChecksum: String?
    ) {
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
            if let override = (localOverrides[InternalStore.gatesKey] as? [String: Bool])?[forName]
            {
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
            if let override =
                (localOverrides[InternalStore.configsKey] as? [String: [String: Any]])?[forName]
            {
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

    func getLayer(client: StatsigClient?, forName layerName: String, keepDeviceValue: Bool) -> Layer
    {
        let latestValue: Layer = storeQueue.sync {
            if let override =
                (localOverrides[InternalStore.layerConfigsKey] as? [String: [String: Any]])?[
                    layerName]
            {
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
            if let override =
                (localOverrides[InternalStore.paramStoresKey] as? [String: [String: Any]])?[
                    storeName]
            {
                return ParameterStore(
                    name: storeName,
                    evaluationDetails: cache.getEvaluationDetails(.LocalOverride),
                    client: client,
                    configuration: override.mapValues {
                        [
                            "ref_type": "static",
                            "param_type": getTypeOfValue($0) ?? "unknown",
                            "value": $0,
                        ]
                    }
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

            DispatchQueue.global().async {
                StatsigUserDefaults.defaults.setDictionarySafe(
                    cacheByID, forKey: UserDefaultsKeys.localStorageKey)
                StatsigUserDefaults.defaults.setDictionarySafe(
                    cacheKeyMapping, forKey: UserDefaultsKeys.cacheKeyMappingKey)
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
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.DEPRECATED_localStorageKey)
        StatsigUserDefaults.defaults.removeObject(forKey: UserDefaultsKeys.localStorageKey)
        StatsigUserDefaults.defaults.removeObject(forKey: UserDefaultsKeys.cacheKeyMappingKey)
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.DEPRECATED_stickyUserExperimentsKey)
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.stickyDeviceExperimentsKey)
        StatsigUserDefaults.defaults.removeObject(forKey: UserDefaultsKeys.networkFallbackInfoKey)
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.DEPRECATED_stickyUserIDKey)
        StatsigUserDefaults.defaults.removeObject(forKey: UserDefaultsKeys.localOverridesKey)
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
            self?.saveOverrides()
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
        StatsigUserDefaults.defaults.setDictionarySafe(
            localOverrides, forKey: UserDefaultsKeys.localOverridesKey)
    }

    private static func getEmptyOverrides() -> [String: Any] {
        return [
            InternalStore.gatesKey: [:],
            InternalStore.configsKey: [:],
            InternalStore.layerConfigsKey: [:],
            InternalStore.paramStoresKey: [:],
        ]
    }

    // Sticky Logic: https://gist.github.com/daniel-statsig/3d8dfc9bdee531cffc96901c1a06a402
    private func getPossiblyStickyValue<T: ConfigProtocol>(
        _ name: String,
        latestValue: T,
        keepDeviceValue: Bool,
        isLayer: Bool,
        factory: (_ name: String, _ data: [String: Any]) -> T
    ) -> T {
        return storeQueue.sync {
            if !keepDeviceValue {
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
                latestExperimentValue = cache.getConfig(
                    stickyValue["allocated_experiment_name"] as? String ?? "")
            } else {
                latestExperimentValue = latestValue
            }

            if latestExperimentValue?.isExperimentActive == true {
                return factory(name, stickyValue)
            }

            if latestValue.isExperimentActive == true {
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
