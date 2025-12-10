import Foundation

@available(*, deprecated, message: "Use `ResultCompletionBlock` instead")
public typealias completionBlock = ((_ error: String?) -> Void)?
public typealias ResultCompletionBlock = ((_ error: StatsigClientError?) -> Void)

public class Statsig {
    internal static var client: StatsigClient?
    internal static var pendingListeners: [StatsigListening] = []
    internal static let initLock = NSLock()

    /**
     Initializes the Statsig SDK. Fetching latest values from Statsig.
     Default values will be returned until initialization is compelete.

     Parameters:
     - sdkKey: The client SDK key copied from console.statsig.com
     - user: The user to check values against
     - options: Configuration options for the Statsig SDK
     - completion: A callback function for when initialization completes. If an error occurred during initialization, a `StatsigClientError` object will be passed to the callback.

     SeeAlso: [Initialization Documentation](https://docs.statsig.com/client/iosClientSDK#step-3---initialize-the-sdk)
     */
    public static func initialize(sdkKey: String, user: StatsigUser? = nil, options: StatsigOptions? = nil,
                             completion: ResultCompletionBlock? = nil)
    {
        guard initLock.try() else {
            completion?(StatsigClientError(.alreadyStarted))
            return
        }
        defer { initLock.unlock() }

        if client != nil {
            completion?(StatsigClientError(.alreadyStarted))
            return
        }

        if sdkKey.isEmpty || sdkKey.starts(with: "secret-") {
            completion?(StatsigClientError(.invalidClientSDKKey))
            return
        }

        func _initialize() {
            Diagnostics.mark?.initialize.createCache.end(success: true)
            client = StatsigClient(sdkKey: sdkKey, user: user, options: options, completionWithResult: completion)
            addPendingListeners()
        }

        if options?.enableCacheByFile == true {
            Diagnostics.mark?.initialize.createCache.start(type: .file)
            ensureMainThread {
                StatsigUserDefaults.defaults = FileBasedUserDefaults()
                _initialize()
            }
        } else if let storageProvider = options?.storageProvider {
            Diagnostics.mark?.initialize.createCache.start(type: .provider)
            StatsigUserDefaults.defaults = StorageProviderBasedUserDefaults(storageProvider: storageProvider)
            _initialize()
        } else {
            Diagnostics.mark?.initialize.createCache.start(type: .user_defaults)
            _initialize()
        }
    }

    /**
     Whether Statsig initialization has been completed.

     SeeAlso [StatsigListening](https://docs.statsig.com/client/iosClientSDK#statsiglistening)
     */
    public static func isInitialized() -> Bool {
        guard let client = client else {
            PrintHandler.log("[Statsig]: Statsig.start has not been called.")
            return false
        }

        return client.isInitialized()
    }

    /**
     Adds a delegate to be called during initializaiton and update user steps.

     Parameters:
     - listener: The class that implements the StatsigListening protocol

     SeeAlso [StatsigListening](https://docs.statsig.com/client/iosClientSDK#statsiglistening)
     */
    public static func addListener(_ listener: StatsigListening)
    {
        guard let client = client else {
            pendingListeners.append(listener)
            return
        }

        client.addListener(listener)
    }

    /**
     Gets the boolean result of a gate for the current user. An exposure event will automatically be logged for the given gate.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public static func checkGate(_ gateName: String) -> Bool {
        return checkGateImpl(gateName, withExposures: true, functionName: funcName()).value
    }

    /**
     Gets the boolean result of a gate for the current user. No exposure events will be logged.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public static func checkGateWithExposureLoggingDisabled(_ gateName: String) -> Bool {
        return checkGateImpl(gateName, withExposures: false, functionName: funcName()).value
    }

    /**
     Get the value for the given feature gate

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public static func getFeatureGate(_ gateName: String) -> FeatureGate {
        return checkGateImpl(gateName, withExposures: true, functionName: funcName())
    }

    /**
     Get the value for the given feature gate. No exposure event will be logged.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public static func getFeatureGateWithExposureLoggingDisabled(_ gateName: String) -> FeatureGate {
        return checkGateImpl(gateName, withExposures: false, functionName: funcName())
    }

    /**
     Logs an exposure event for the given gate. Only required if a related checkGateWithExposureLoggingDisabled call has been made.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com
     */
    public static func manuallyLogGateExposure(_ gateName: String) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogGateExposure")).")
            return
        }

        client.manuallyLogGateExposure(gateName)
    }

    /**
     Get the values for the given experiment or autotune. An exposure event will automatically be logged for the given experiment.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     - keepDeviceValue: Locks experiment values to the first time they are received. If an experiment changes, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Experiments Documentation](https://docs.statsig.com/experiments-plus)
     */
    public static func getExperiment(_ experimentName: String, keepDeviceValue: Bool = false) -> DynamicConfig {
        return getExperimentImpl(experimentName, keepDeviceValue: keepDeviceValue, withExposures: true, functionName: funcName())
    }

    /**
     Get the values for the given experiment. No exposure events will be logged.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     - keepDeviceValue: Locks experiment values to the first time they are received. If an experiment changes, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Experiments Documentation](https://docs.statsig.com/experiments-plus)
     */
    public static func getExperimentWithExposureLoggingDisabled(_ experimentName: String, keepDeviceValue: Bool = false) -> DynamicConfig {
        return getExperimentImpl(experimentName, keepDeviceValue: keepDeviceValue, withExposures: false, functionName: funcName())
    }

    /**
     Logs an exposure event for the given experiment. Only required if a related getExperimentWithExposureLoggingDisabled has been made.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     */
    public static func manuallyLogExperimentExposure(_ experimentName: String, keepDeviceValue: Bool = false) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogExperimentExposure")).")
            return
        }

        client.manuallyLogExperimentExposure(experimentName, keepDeviceValue: keepDeviceValue)
    }

    /**
     Get the values for the given dynamic config. An exposure event will automatically be logged for the given dynamic config.

     Parameters:
     - configName: The name of the dynamic config setup on console.statsig.com

     SeeAlso [Dynamic Config Documentation](https://docs.statsig.com/dynamic-config)
     */
    public static func getConfig(_ configName: String) -> DynamicConfig {
        return getConfigImpl(configName, withExposures: true, functionName: funcName())
    }

    /**
     Get the values for the given dynamic config. No exposure event will be logged.

     Parameters:
     - configName: The name of the dynamic config setup on console.statsig.com

     SeeAlso [Dynamic Config Documentation](https://docs.statsig.com/dynamic-config)
     */
    public static func getConfigWithExposureLoggingDisabled(_ configName: String) -> DynamicConfig {
        return getConfigImpl(configName, withExposures: false, functionName: funcName())
    }

    /**
     Logs an exposure event for the given dynamic config. Only required if a related getConfigWithExposureLoggingDisabled call has been made.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     */
    public static func manuallyLogConfigExposure(_ configName: String) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogConfigExposure")).")
            return
        }

        client.manuallyLogConfigExposure(configName)
    }

    /**
     Get the values for the given layer. Exposure events will be fired when getValue is called on the result Layer class.

     Parameters:
     - layerName: The name of the layer setup on console.statsig.com
     - keepDeviceValue: Locks layer values to the first time they are received. If an layer values change, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Layers Documentation](https://docs.statsig.com/layers)
     */
    public static func getLayer(_ layerName: String, keepDeviceValue: Bool = false) -> Layer {
        return getLayerImpl(layerName, keepDeviceValue: keepDeviceValue, withExposures: true, functionName: funcName())
    }

    /**
     Get the values for the given layer. No exposure events will be fired.

     Parameters:
     - layerName: The name of the layer setup on console.statsig.com
     - keepDeviceValue: Locks layer values to the first time they are received. If an layer values change, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Layers Documentation](https://docs.statsig.com/layers)
     */
    public static func getLayerWithExposureLoggingDisabled(_ layerName: String, keepDeviceValue: Bool = false) -> Layer {
        return getLayerImpl(layerName, keepDeviceValue: keepDeviceValue, withExposures: false, functionName: funcName())
    }

    /**
     Logs an exposure event for the given layer parameter. Only required if a related getLayerWithExposureLoggingDisabled call has been made.

     Parameters:
     - layerName: The name of the layer setup on console.statsig.com
     - parameterName: The name of the parameter that was checked.
     */
    public static func manuallyLogLayerParameterExposure(_ layerName: String, _ parameterName: String, keepDeviceValue: Bool = false) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogLayerParameterExposure")).")
            return
        }

        client.manuallyLogLayerParameterExposure(layerName, parameterName, keepDeviceValue: keepDeviceValue)
    }

    /**
     Get the values for the given parameter store. Exposure events will be fired when getValue is called on the result ParameterStore class.

     Parameters:
     - storeName: The name of the parameter store setup on console.statsig.com

     SeeAlso [Parameter Stores Documentation](https://docs.statsig.com/client/concepts/parameter-stores/)
     */
    public static func getParameterStore(
        _ storeName: String
    ) -> ParameterStore {
        return getParameterStoreImpl(
            storeName,
            withExposures: true,
            functionName: funcName()
        )
    }
    
    /**
     Get the values for the given parameter store. No exposure events will be fired.

     Parameters:
     - storeName: The name of the parameter store setup on console.statsig.com

     SeeAlso [Parameter Stores Documentation](https://docs.statsig.com/client/concepts/parameter-stores/)
     */
    public static func getParameterStoreWithExposureLoggingDisabled(
        _ storeName: String
    ) -> ParameterStore {
        return getParameterStoreImpl(
            storeName,
            withExposures: false,
            functionName: funcName()
        )
    }

    /**
     Logs an exposure event for the given feature gate. Only required if a related getFeatureGateWithExposureLoggingDisabled call has been made.

     Parameters:
     - gate: The the feature gate class of a feature gate setup on console.statsig.com
     */
    public static func manuallyLogExposure(_ gate: FeatureGate) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogExposure")).")
            return
        }

        client.manuallyLogExposure(gate)
    }

    /**
     Logs an exposure event for the given dynamic config. Only required if a related getConfigWithExposureLoggingDisabled or getExperimentWithExposureLoggingDisabled call has been made.

     Parameters:
     - config: The dynamic config class of an experiment, autotune, or dynamic config setup on console.statsig.com
     */
    public static func manuallyLogExposure(_ config: DynamicConfig) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogExposure")).")
            return
        }

        client.manuallyLogExposure(config)
    }

    /**
     Logs an exposure event for the given layer. Only required if a related getLayerWithExposureLoggingDisabled call has been made.

     Parameters:
     - layer: The layer class of a layer setup on console.statsig.com
     - paramterName: The name of the layer parameter that was checked
     */
    public static func manuallyLogExposure(_ layer: Layer, parameterName: String) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("manuallyLogExposure")).")
            return
        }

        client.logLayerParameterExposureForLayer(layer, parameterName: parameterName, isManualExposure: true)
    }

    /**
     Logs an event to Statsig with the provided values.

     Parameters:
     - withName: The name of the event
     - metadata: Any extra values to be logged with the event
     */
    public static func logEvent(_ withName: String, metadata: [String: String]? = nil) {
        client?.logEvent(withName, metadata: metadata)
    }

    /**
     Logs an event to Statsig with the provided values.

     Parameters:
     - withName: The name of the event
     - value: A top level value for the event
     - metadata: Any extra values to be logged with the event
     */
    public static func logEvent(_ withName: String, value: String, metadata: [String: String]? = nil) {
        client?.logEvent(withName, value: value, metadata: metadata)
    }

    /**
     Logs an event to Statsig with the provided values.

     Parameters:
     - withName: The name of the event
     - value: A top level value for the event
     - metadata: Any extra key/value pairs to be logged with the event
     */
    public static func logEvent(_ withName: String, value: Double, metadata: [String: String]? = nil) {
        client?.logEvent(withName, value: value, metadata: metadata)
    }

    /**
     Switches the user and pulls new values for that user from Statsig.
     If `values` passed in, updates ther user using these values rather than fetching updates.
     Default values will be returned until the update is complete.

     Parameters:
     - user: The new user
     - values: The updated values to be associated with the user.
     - completion: A callback block called when the new values/update operation have been received. May be called with a `StatsigClientError` object if the fetch fails.
     */
    public static func updateUserWithResult(_ user: StatsigUser, values: [String: Any]? = nil, completion: ResultCompletionBlock? = nil) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage("updateUser")).")
            completion?(StatsigClientError(.clientUnstarted, message: "\(getUnstartedErrorMessage("updateUser"))."))
            return
        }

        client.updateUserWithResult(user, values: values, completion: completion)
    }

    /**
     Manually triggered the refreshing process for the current user

     Parameters:
     - completion: A callback block called when the new values/update operation have been received. May be called with a `StatsigClientError` object if the fetch fails.
     */
    public static func refreshCacheWithResult(_ completion: ResultCompletionBlock? = nil) {
        guard let client: StatsigClient = client else {
            let message = getUnstartedErrorMessage()
            PrintHandler.log("[Statsig]: \(message).")
            completion?(StatsigClientError(.clientUnstarted, message: message))
            return
        }

        client.refreshCacheWithResult(completion)
    }

    /**
     Stops all Statsig activity and flushes any pending events.
     */
    public static func shutdown() {
        client?.shutdown()
        client = nil
    }

    /**
     Manually triggers a flush of any queued events.
     */
    public static func flush() {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage()).")
            return
        }

        client.flush()
    }

    /**
     Manually triggers a flush of any queued events.
     Currently it's only available for tests.
     */
    internal static func flush(completion: @escaping (() -> Void)) {
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage()).")
            return
        }

        client.flush(completion: completion)
    }
    
    /**
      Updates mutable-at-runtime options.
      */
     public static func updateOptions(eventLoggingEnabled: Bool? = nil) {
         guard let client = client else {
             PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage()).")
             return
         }
         client.updateOptions(eventLoggingEnabled: eventLoggingEnabled)
     }

    /**
     The generated identifier that exists across users
     */
    public static func getStableID() -> String? {
        return client?.getStableID()
    }

    /**
     The generated identifier for this session
     */
    public static func getSessionID() -> String? {
        return client?.getSessionID()
    }
    
    /**
     The  statsigMetadata included by the SDK on events
     */
    public static func getStatsigMetadata() -> StatsigMetadata? {
        return client?.getStatsigMetadata()
    }

    /**
     Sets a value to be returned for the given gate instead of the actual evaluated value.

     Parameters:
     - gateName: The name of the gate to be overridden
     - value: The value that will be returned
     */
    public static func overrideGate(_ gateName: String, value: Bool) {
        client?.overrideGate(gateName, value: value)
    }

    /**
     Sets a value to be returned for the given dynamic config/experiment instead of the actual evaluated value.

     Parameters:
     - configName: The name of the config or experiment to be overridden
     - value: The value that the resulting DynamicConfig will contain
     */
    public static func overrideConfig(_ configName: String, value: [String: Any]) {
        client?.overrideConfig(configName, value: value)
    }

    /**
     Sets a value to be returned for the given layer instead of the actual evaluated value.

     Parameters:
     - layerName: The name of the layer to be overridden
     - value: The value that the resulting Layer will contain
     */
    public static func overrideLayer(_ layerName: String, value: [String: Any]) {
        client?.overrideLayer(layerName, value: value)
    }

    /**
     Sets a value to be returned for the given parameter store instead of following the actual ref in the store.

     Parameters:
     - storeName: The name of the config or experiment to be overridden
     - value: Dictionary where keys are property names and values are static ref values in the overridden store
     */
    public static func overrideParamStore(_ storeName: String, value: [String: Any]) {
        client?.overrideParamStore(storeName, value: value)
    }

    /**
     Clears any overridden value for the given gate/dynamic config/experiment.

     Parameters:
     - name: The name of the gate/dynamic config/experiment to clear
     */
    public static func removeOverride(_ name: String) {
        client?.removeOverride(name)
    }

    /**
     Clears all overriden values.
     */
    public static func removeAllOverrides() {
        client?.removeAllOverrides()
    }

    /**
     Returns all values that are currently overriden.
     */
    public static func getAllOverrides() -> StatsigOverrides? {
        var result: StatsigOverrides? = nil
        result = client?.getAllOverrides()
        return result
    }

    /**
     Presents a view of the current internal state of the SDK.
     */
    public static func openDebugView(_ callback: DebuggerCallback? = nil) {
        client?.openDebugView(callback)
    }

    /**
     Returns the raw values that the SDK is using internally to provide gate/config/layer results
     */
    public static func getInitializeResponseJson() -> ExternalInitializeResponse {
        var result = ExternalInitializeResponse.uninitialized()
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage()).")
            return result
        }
        result = client.getInitializeResponseJson()
        return result
    }

    //
    // MARK: - Private
    //

    private static func checkGateImpl(_ gateName: String, withExposures: Bool, functionName: String) -> FeatureGate {
        var result: FeatureGate = FeatureGate(
            name: gateName,
            value: false,
            ruleID: "",
            evalDetails: .uninitialized())
     
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage(functionName)). Returning false as the default.")
            return result
        }

        result = withExposures
        ? client.getFeatureGate(gateName)
        : client.getFeatureGateWithExposureLoggingDisabled(gateName)
        
        return result
    }

    private static func getExperimentImpl(_ experimentName: String, keepDeviceValue: Bool, withExposures: Bool, functionName: String) -> DynamicConfig {
        var result: DynamicConfig = getEmptyConfig(experimentName)
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage(functionName)). Returning a dummy DynamicConfig that will only return default values.")
            return result
        }

        result = withExposures
        ? client.getExperiment(experimentName, keepDeviceValue: keepDeviceValue)
        : client.getExperimentWithExposureLoggingDisabled(experimentName, keepDeviceValue: keepDeviceValue)
        return result
    }

    private static func getConfigImpl(_ configName: String, withExposures: Bool, functionName: String) -> DynamicConfig {
        var result: DynamicConfig = getEmptyConfig(configName)
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage(functionName)). Returning a dummy DynamicConfig that will only return default values.")
            return result
        }

        result = withExposures
        ? client.getConfig(configName)
        : client.getConfigWithExposureLoggingDisabled(configName)
        return result
    }

    private static func getLayerImpl(
        _ layerName: String,
        keepDeviceValue: Bool,
        withExposures: Bool,
        functionName: String
    ) -> Layer {
        var result: Layer = Layer(client: nil, name: layerName, evalDetails: .uninitialized())
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage(functionName)). Returning an empty Layer object")
            return result
        }

        result = withExposures
        ? client.getLayer(layerName, keepDeviceValue: keepDeviceValue)
        : client.getLayerWithExposureLoggingDisabled(layerName, keepDeviceValue: keepDeviceValue)
        return result
    }
    
    private static func getParameterStoreImpl(
        _ storeName: String,
        withExposures: Bool,
        functionName: String
    ) -> ParameterStore {
        var result = ParameterStore(
            name: storeName,
            evaluationDetails: .uninitialized()
        )
        guard let client = client else {
            PrintHandler.log("[Statsig]: \(getUnstartedErrorMessage(functionName)). Returning a dummy ParameterStore that will only return default values.")
            return result
        }
        
        result = withExposures ? client.getParameterStore(storeName) : client.getParameterStoreWithExposureLoggingDisabled(storeName)
        return result
    }

    private static func getEmptyConfig(_ name: String) -> DynamicConfig {
        return DynamicConfig(configName: name, evalDetails: .uninitialized())
    }

    private static func addPendingListeners() {
        for listener in pendingListeners {
            client?.addListener(listener)
        }
        pendingListeners.removeAll()
    }

    private static func funcName(_ name: String = #function) -> String {
        return name.components(separatedBy: "(").first ?? name
    }

    private static func getUnstartedErrorMessage(_ functionName: String = #function) -> String {
        return "Must start Statsig first and wait for it to complete before calling \(functionName)"
    }

    // MARK: Deprecated

    /**
     Initializes the Statsig SDK. Fetching latest values from Statsig.
     Default values will be returned until initialization is compelete.

     Parameters:
     - sdkKey: The client SDK key copied from console.statsig.com
     - user: The user to check values against
     - options: Configuration options for the Statsig SDK
     - completion: A callback function for when initialization completes. If an error occurred during initialization, a error message string will be passed to the callback.

     SeeAlso: [Initialization Documentation](https://docs.statsig.com/client/iosClientSDK#step-3---initialize-the-sdk)
     */
    @available(*, deprecated, message: "Use `Statsig.initialize` instead")
    public static func start(sdkKey: String, user: StatsigUser? = nil, options: StatsigOptions? = nil,
                             completion: completionBlock = nil)
    {
        return initialize(sdkKey: sdkKey, user: user, options: options) { error in
            completion?(error?.message)
        }
    }

    /**
     Switches the user and pulls new values for that user from Statsig.
     If `values` passed in, updates ther user using these values rather than fetching updates.
     Default values will be returned until the update is complete.

     Parameters:
     - user: The new user
     - values: The updated values to be associated with the user.
     - completion: A callback block called when the new values/update operation have been received. May be called with an error message string if the fetch fails.
     */
    @available(*, deprecated, message: "Use `Statsig.updateUserWithResult` instead")
    public static func updateUser(_ user: StatsigUser, values: [String: Any]? = nil, completion: completionBlock = nil) {
        Statsig.updateUserWithResult(user, values: values) { error in
            completion?(error?.message)
        }
    }
    
    /**
     Manually triggered the refreshing process for the current user

     Parameters:
     - completion: A callback block called when the new values/update operation have been received. May be called with an error message string if the fetch fails.
     */
    @available(*, deprecated, message: "Use `Statsig.refreshCacheWithResult` instead")
    public static func refreshCache(_ completion: completionBlock = nil) {
        Statsig.refreshCacheWithResult { error in
            completion?(error?.message)
        }
    }
    
    public static func getEvaluationSource() -> EvaluationSource? {
        return client?.getEvaluationSource()
    }
}
