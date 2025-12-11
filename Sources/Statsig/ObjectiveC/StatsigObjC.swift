import Foundation

@objc(Statsig)
public final class StatsigObjC: NSObject {

    //
    // MARK: - Initialize
    //

    @objc public static func initialize(withSDKKey: String) {
        Statsig.initialize(sdkKey: withSDKKey)
    }

    @objc public static func initialize(withSDKKey: String, user: StatsigUserObjC) {
        Statsig.initialize(sdkKey: withSDKKey, user: user.user)
    }

    @objc public static func initialize(withSDKKey: String, options: StatsigOptionsObjC) {
        Statsig.initialize(sdkKey: withSDKKey, options: options.optionsInternal)
    }

    @objc public static func initialize(withSDKKey: String, completion: ResultCompletionBlock?) {
        Statsig.initialize(sdkKey: withSDKKey, completion: completion)
    }

    @objc public static func initialize(
        withSDKKey: String, user: StatsigUserObjC, completion: ResultCompletionBlock?
    ) {
        Statsig.initialize(sdkKey: withSDKKey, user: user.user, completion: completion)
    }

    @objc public static func initialize(
        withSDKKey: String, user: StatsigUserObjC, options: StatsigOptionsObjC
    ) {
        Statsig.initialize(sdkKey: withSDKKey, user: user.user, options: options.optionsInternal)
    }

    @objc public static func initialize(
        withSDKKey: String, options: StatsigOptionsObjC, completion: ResultCompletionBlock?
    ) {
        Statsig.initialize(
            sdkKey: withSDKKey, options: options.optionsInternal, completion: completion)
    }

    @objc public static func initialize(
        withSDKKey: String, user: StatsigUserObjC, options: StatsigOptionsObjC,
        completion: ResultCompletionBlock?
    ) {
        Statsig.initialize(
            sdkKey: withSDKKey, user: user.user, options: options.optionsInternal,
            completion: completion)
    }

    //
    // MARK: - Update User
    //

    @objc public static func updateUserWithResult(newUser: StatsigUserObjC) {
        Statsig.updateUserWithResult(newUser.user, completion: nil)
    }

    @objc public static func updateUserWithResult(
        newUser: StatsigUserObjC, completion: ResultCompletionBlock?
    ) {
        Statsig.updateUserWithResult(newUser.user, completion: completion)
    }

    //
    // MARK: - Refresh Cache
    //

    @objc public static func refreshCacheWithResult() {
        Statsig.refreshCacheWithResult()
    }

    @objc public static func refreshCacheWithResult(completion: ResultCompletionBlock?) {
        Statsig.refreshCacheWithResult(completion)
    }

    //
    // MARK: - Shutdown
    //

    @objc public static func shutdown() {
        Statsig.shutdown()
    }

    //
    // MARK: - Check Gate
    //

    @objc public static func checkGate(forName: String) -> Bool {
        return Statsig.checkGate(forName)
    }

    @objc public static func checkGateWithExposureLoggingDisabled(_ gateName: String) -> Bool {
        return Statsig.checkGateWithExposureLoggingDisabled(gateName)
    }

    @objc public static func getFeatureGateWithExposureLoggingDisabled(_ gateName: String)
        -> FeatureGateObjC
    {
        return FeatureGateObjC(
            withGate: Statsig.getFeatureGateWithExposureLoggingDisabled(gateName))
    }

    //
    // MARK: - Get Config
    //

    @objc public static func getConfig(forName: String) -> DynamicConfigObjC {
        return DynamicConfigObjC(withConfig: Statsig.getConfig(forName))
    }

    @objc public static func getConfigWithExposureLoggingDisabled(_ configName: String)
        -> DynamicConfigObjC
    {
        return DynamicConfigObjC(
            withConfig: Statsig.getConfigWithExposureLoggingDisabled(configName))
    }

    //
    // MARK: - Get Experiment
    //

    @objc public static func getExperiment(forName: String) -> DynamicConfigObjC {
        return getExperiment(forName: forName, keepDeviceValue: false)
    }

    @objc public static func getExperiment(forName: String, keepDeviceValue: Bool)
        -> DynamicConfigObjC
    {
        return DynamicConfigObjC(
            withConfig: Statsig.getExperiment(forName, keepDeviceValue: keepDeviceValue))
    }

    @objc public static func getExperimentWithExposureLoggingDisabled(_ experimentName: String)
        -> DynamicConfigObjC
    {
        return getExperimentWithExposureLoggingDisabled(experimentName, keepDeviceValue: false)
    }

    @objc public static func getExperimentWithExposureLoggingDisabled(
        _ experimentName: String, keepDeviceValue: Bool
    ) -> DynamicConfigObjC {
        return DynamicConfigObjC(
            withConfig: Statsig.getExperimentWithExposureLoggingDisabled(
                experimentName, keepDeviceValue: keepDeviceValue))
    }

    //
    // MARK: - Get Layer
    //

    @objc public static func getLayer(forName: String) -> LayerObjC {
        return getLayer(forName: forName, keepDeviceValue: false)
    }

    @objc public static func getLayer(forName: String, keepDeviceValue: Bool) -> LayerObjC {
        return LayerObjC(Statsig.getLayer(forName, keepDeviceValue: keepDeviceValue))
    }

    @objc public static func getLayerWithExposureLoggingDisabled(_ layerName: String) -> LayerObjC {
        return getLayerWithExposureLoggingDisabled(layerName, keepDeviceValue: false)
    }

    @objc public static func getLayerWithExposureLoggingDisabled(
        _ layerName: String, keepDeviceValue: Bool
    ) -> LayerObjC {
        return LayerObjC(
            Statsig.getLayerWithExposureLoggingDisabled(layerName, keepDeviceValue: keepDeviceValue)
        )
    }

    //
    // MARK: - Get Parameter Store
    //

    @objc public static func getParameterStoreForName(_ storeName: String) -> ParameterStoreObjC {
        return ParameterStoreObjC(withParameterStore: Statsig.getParameterStore(storeName))
    }

    @objc public static func getParameterStoreWithExposureLoggingDisabled(_ storeName: String)
        -> ParameterStoreObjC
    {
        return ParameterStoreObjC(
            withParameterStore: Statsig.getParameterStoreWithExposureLoggingDisabled(storeName))
    }

    //
    // MARK: - Manual Exposure Logging (Simple)
    //

    @objc public static func manuallyLogGateExposure(_ gateName: String) {
        Statsig.manuallyLogGateExposure(gateName)
    }

    @objc public static func manuallyLogConfigExposure(_ configName: String) {
        Statsig.manuallyLogConfigExposure(configName)
    }

    @objc public static func manuallyLogExperimentExposure(_ experimentName: String) {
        manuallyLogExperimentExposure(experimentName, keepDeviceValue: false)
    }

    @objc public static func manuallyLogExperimentExposure(
        _ experimentName: String, keepDeviceValue: Bool
    ) {
        Statsig.manuallyLogExperimentExposure(experimentName, keepDeviceValue: keepDeviceValue)
    }

    @objc public static func manuallyLogLayerParameterExposure(
        _ layerName: String, parameterName: String
    ) {
        manuallyLogLayerParameterExposure(
            layerName, parameterName: parameterName, keepDeviceValue: false)
    }

    @objc public static func manuallyLogLayerParameterExposure(
        _ layerName: String, parameterName: String, keepDeviceValue: Bool
    ) {
        Statsig.manuallyLogLayerParameterExposure(
            layerName, parameterName, keepDeviceValue: keepDeviceValue)
    }

    //
    // MARK: - Manual Exposure Logging (Advanced)
    //

    @objc public static func manuallyLogExposureWithFeatureGate(_ gate: FeatureGateObjC) {
        Statsig.manuallyLogExposure(gate.gate)
    }

    @objc public static func manuallyLogExposureWithDynamicConfig(_ config: DynamicConfigObjC) {
        Statsig.manuallyLogExposure(config.config)
    }

    @objc public static func manuallyLogExposureWithLayer(_ layer: LayerObjC, parameterName: String)
    {
        Statsig.manuallyLogExposure(layer.layer, parameterName: parameterName)
    }

    //
    // MARK: - Log Event
    //

    @objc public static func logEvent(_ withName: String) {
        Statsig.logEvent(withName)
    }

    @objc public static func logEvent(_ withName: String, stringValue: String) {
        Statsig.logEvent(withName, value: stringValue)
    }

    @objc public static func logEvent(_ withName: String, doubleValue: Double) {
        Statsig.logEvent(withName, value: doubleValue)
    }

    @objc public static func logEvent(_ withName: String, metadata: [String: String]) {
        Statsig.logEvent(withName, metadata: metadata)
    }

    @objc public static func logEvent(
        _ withName: String, stringValue: String, metadata: [String: String]
    ) {
        Statsig.logEvent(withName, value: stringValue, metadata: metadata)
    }

    @objc public static func logEvent(
        _ withName: String, doubleValue: Double, metadata: [String: String]
    ) {
        Statsig.logEvent(withName, value: doubleValue, metadata: metadata)
    }

    //
    // MARK: - Overrides
    //

    @objc public static func overrideGate(_ gateName: String, value: Bool) {
        Statsig.overrideGate(gateName, value: value)
    }

    @objc public static func overrideConfig(_ configName: String, value: [String: Any]) {
        Statsig.overrideConfig(configName, value: value)
    }

    @objc public static func overrideLayer(_ layerName: String, value: [String: Any]) {
        Statsig.overrideLayer(layerName, value: value)
    }

    @objc public static func overrideParameterStore(_ storeName: String, value: [String: Any]) {
        Statsig.overrideParamStore(storeName, value: value)
    }

    @objc public static func removeOverride(_ overrideName: String) {
        Statsig.removeOverride(overrideName)
    }

    @objc public static func removeAllOverrides() {
        Statsig.removeAllOverrides()
    }

    @objc public static func getAllOverrides() -> StatsigOverridesObjC? {
        StatsigOverridesObjC(Statsig.getAllOverrides())
    }

    //
    // MARK: - Statsig Listening
    //

    @objc public static func addListener(listener: StatsigListening) {
        Statsig.addListener(listener)
    }

    @objc public static func isInitialized() -> Bool {
        return Statsig.isInitialized()
    }

    //
    // MARK: - Misc
    //

    @objc public static func getStableID() -> String? {
        return Statsig.getStableID()
    }

    @objc public static func openDebugView() {
        Statsig.openDebugView()
    }

    //
    // MARK: - Deprecated
    //

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(withSDKKey: String) {
        Statsig.start(sdkKey: withSDKKey)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(withSDKKey: String, user: StatsigUserObjC) {
        Statsig.start(sdkKey: withSDKKey, user: user.user)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(withSDKKey: String, options: StatsigOptionsObjC) {
        Statsig.start(sdkKey: withSDKKey, options: options.optionsInternal)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(withSDKKey: String, completion: completionBlock) {
        Statsig.start(sdkKey: withSDKKey, completion: completion)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(
        withSDKKey: String, user: StatsigUserObjC, completion: completionBlock
    ) {
        Statsig.start(sdkKey: withSDKKey, user: user.user, completion: completion)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(
        withSDKKey: String, user: StatsigUserObjC, options: StatsigOptionsObjC
    ) {
        Statsig.start(sdkKey: withSDKKey, user: user.user, options: options.optionsInternal)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(
        withSDKKey: String, options: StatsigOptionsObjC, completion: completionBlock
    ) {
        Statsig.start(sdkKey: withSDKKey, options: options.optionsInternal, completion: completion)
    }

    @available(*, deprecated, message: "Implement `initialize` instead")
    @objc public static func start(
        withSDKKey: String, user: StatsigUserObjC, options: StatsigOptionsObjC,
        completion: completionBlock
    ) {
        Statsig.start(
            sdkKey: withSDKKey, user: user.user, options: options.optionsInternal,
            completion: completion)
    }

    @available(*, deprecated, message: "Implement `updateUserWithResult` instead")
    @objc public static func updateUser(newUser: StatsigUserObjC) {
        Statsig.updateUser(newUser.user, completion: nil)
    }

    @available(*, deprecated, message: "Implement `updateUserWithResult` instead")
    @objc public static func updateUser(newUser: StatsigUserObjC, completion: completionBlock) {
        Statsig.updateUser(newUser.user, completion: completion)
    }
}
