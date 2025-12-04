import Foundation

public class StatsigClient {
    internal var logger: EventLogger
    internal var statsigOptions: StatsigOptions

    private var sdkKey: String
    private var currentUser: StatsigUser
    private var store: InternalStore
    private var networkService: NetworkService
    private var syncTimer: Timer?
    // We use a list of functions to keep a weak reference to each listener. Using
    // NSHashTable.weakObjects isn't an option, as objects are only deallocated when
    // inside an autoreleasepool block. See https://github.com/GitHawkApp/FlatCache/issues/3
    private var listeners: [() -> StatsigListening?] = []
    private var hasInitialized: Bool = false
    private var lastInitializeError: StatsigClientError?
    private var completionWithResult: ResultCompletionBlock? = nil

    let maxEventNameLength = 64

    /**
     Initializes the Statsig SDK. Fetching latest values from Statsig.
     Default values will be returned until initialization is compelete.

     Parameters:
     - sdkKey: The client SDK key copied from console.statsig.com
     - user: The user to check values against
     - options: Configuration options for the Statsig SDK
     - completionWithResult: A callback function for when initialization completes. If an error occurred during initialization, a `StatsigClientError` object will be passed to the callback.
     - completion (deprecated. use completionWithResult): A callback function for when initialization completes. If an error occurred during initialization, an error message string will be passed to the callback.

     SeeAlso: [Initialization Documentation](https://docs.statsig.com/client/iosClientSDK#step-3---initialize-the-sdk)
     */
    public init(
        sdkKey: String,
        user: StatsigUser? = nil,
        options: StatsigOptions? = nil,
        completionWithResult: ResultCompletionBlock? = nil,
        completion: ((_ error: String?) -> Void)? = nil
    ) {
        Diagnostics.boot(options)
        Diagnostics.mark?.overall.start();

        self.sdkKey = sdkKey
        let normalizedUser = StatsigClient.normalizeUser(user, options: options)
        self.currentUser = normalizedUser
        self.statsigOptions = options ?? StatsigOptions()
        if let handler = self.statsigOptions.printHandler {
            PrintHandler.setPrintHandler(handler)
        }
        self.store = InternalStore(sdkKey, normalizedUser, options: statsigOptions)
        self.networkService = NetworkService(sdkKey: sdkKey, options: statsigOptions, store: store)
        Diagnostics.mark?.initialize.loggerStart.start()
        self.logger = EventLogger(sdkKey: sdkKey, user: currentUser, networkService: networkService)
        self.logger.start()
        Diagnostics.mark?.initialize.loggerStart.end(success: true)

        subscribeToApplicationLifecycle()

        let _onComplete: (StatsigClientError?) -> Void = { [weak self, completionWithResult, completion] error in
            guard let self = self else {
                return
            }

            if (self.statsigOptions.enableAutoValueUpdate) {
                self.scheduleRepeatingSync()
            }

            self.hasInitialized = true
            self.lastInitializeError = error

            self.logger.retryFailedRequests(forUser: normalizedUser);

            Diagnostics.mark?.overall.end(
                success: error == nil,
                details: self.store.cache.getEvaluationDetails(),
                errorMessage: error?.message
            )
            Diagnostics.log(self.logger, user: normalizedUser, context: .initialize)

            self.notifyOnInitializedListeners(error)
            completionWithResult?(error)
            completion?(error?.message)
        }

        if (options?.initializeValues != nil) {
            _onComplete(nil)
        } else {
            fetchValuesFromNetwork(
                user: normalizedUser,
                marker: Diagnostics.mark?.initialize.network,
                processMarker: Diagnostics.mark?.initialize.process,
                storeMarker: Diagnostics.mark?.initialize.storeRead,
                completion: _onComplete
            )
        }
    }

    deinit {
        unsubscribeFromApplicationLifecycle()
    }

    /**
     Whether Statsig initialization has been completed.

     SeeAlso [StatsigListening](https://docs.statsig.com/client/iosClientSDK#statsiglistening)
     */
    public func isInitialized() -> Bool {
        return hasInitialized
    }

    /**
     Adds a delegate to be called during initializaiton and update user steps.

     Parameters:
     - listener: The class that implements the StatsigListening protocol

     SeeAlso [StatsigListening](https://docs.statsig.com/client/iosClientSDK#statsiglistening)
     */
    public func addListener(_ listener: StatsigListening) {
        if (hasInitialized) {
            listener.onInitializedWithResult?(lastInitializeError)
            (listener as StatsigListeningInternal).onInitialized?(lastInitializeError?.message)
        }
        listeners.append({ [weak listener] in return listener })
    }

    /**
     Switches the user and pulls new values for that user from Statsig.
     Default values will be returned until the update is complete.

     Parameters:
     - user: The new user
     - completion: A callback block called when the new values have been received. May be called with a `StatsigClientError` object if the fetch fails.
     */
    public func updateUserWithResult(_ user: StatsigUser, values: [String: Any]? = nil, completion: ResultCompletionBlock? = nil) {
        self.logger.clearExposuresDedupeDict()

        self.updateUserImpl(user, values: values, completion: completion)
    }
    
    /**
     Manually triggered the refreshing process for the current user

     Parameters:
     - completion: A callback block called when the new values/update operation have been received. May be called with a `StatsigClientError` object if the fetch fails.
     */
    public func refreshCacheWithResult(_ completion: ResultCompletionBlock? = nil) {
        self.updateUserWithResult(self.currentUser, completion: completion)
    }

    /**
     Stops all Statsig activity and flushes any pending events.
     */
    public func shutdown() {
        logger.stop()
        Diagnostics.shutdown()
        syncTimer?.invalidate()
    }

    /**
     Manually triggers a flush of any queued events.
     */
    public func flush() {
        logger.flush()
    }

    /**
     Updates mutable-at-runtime options.
     */
    public func updateOptions(eventLoggingEnabled: Bool? = nil) {
        if let eventLoggingEnabled = eventLoggingEnabled {
            self.logger.logQueue.async { [weak self] in
                guard let self = self else { return }
                statsigOptions.eventLoggingEnabled = eventLoggingEnabled
                if (eventLoggingEnabled) {
                    logger.retryFailedRequests(forUser: self.currentUser)
                }
            }
        }
    }

    /**
     The generated identifier that exists across users
     */
    public func getStableID() -> String? {
        return currentUser.deviceEnvironment[StatsigMetadata.STABLE_ID_KEY] as? String
    }

    /**
     The generated identifier for this session
     */
    public func getSessionID() -> String? {
        return currentUser.deviceEnvironment[StatsigMetadata.SESSION_ID_KEY] as? String
    }
    
    /**
     The statsigMetadata included by the SDK on events
     */
    public func getStatsigMetadata() -> StatsigMetadata {
        return StatsigMetadata.buildMetadataFromEnvironmentDict(deviceEnvironment: currentUser.deviceEnvironment)
    }

    /**
     Returns the raw values that the SDK is using internally to provide gate/config/layer results
     */
    public func getInitializeResponseJson() -> ExternalInitializeResponse {
        var values: String? = nil
        let dict: [String: Any?] = [
            "feature_gates": self.store.cache.gates,
            "dynamic_configs": self.store.cache.configs,
            "layer_configs": self.store.cache.layers,
            "param_stores": self.store.cache.paramStores,
            "hash_used": self.store.cache.hashUsed,
            "time": self.store.cache.userCache["time"],
            "derived_fields": self.store.cache.userCache["derived_fields"],
            "full_checksum": self.store.cache.userCache["full_checksum"],
            "sdk_flags": self.store.cache.userCache["sdk_flags"],
            "has_updates" : true
        ]

        if JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = data.text {
            values = json
        }

        return ExternalInitializeResponse(
            values: values,
            evaluationDetails: store.cache.getEvaluationDetails()
        )
    }
}

// MARK: Feature Gates
extension StatsigClient {
    /**
     Gets the Bool value of a gate for the current user. An exposure event will automatically be logged for the given gate.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public func checkGate(_ gateName: String) -> Bool {
        return getFeatureGate(gateName).value
    }

    /**
     Gets the FeatureGate result of a gate for the current user. An exposure event will automatically be logged for the given gate.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public func getFeatureGate(_ gateName: String) -> FeatureGate {
        return getFeatureGateImpl(gateName, shouldExpose: true)
    }

    /**
     Gets the boolean result of a gate for the current user. No exposure events will be logged.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public func checkGateWithExposureLoggingDisabled(_ gateName: String) -> Bool {
        return getFeatureGateWithExposureLoggingDisabled(gateName).value
    }

    /**
     Gets the FeatureGate result of a gate for the current user. No exposure events will be logged.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com

     SeeAlso [Gate Documentation](https://docs.statsig.com/feature-gates/working-with)
     */
    public func getFeatureGateWithExposureLoggingDisabled(_ gateName: String) -> FeatureGate {
        return getFeatureGateImpl(gateName, shouldExpose: false)
    }

    private func getFeatureGateImpl(_ gateName: String, shouldExpose: Bool) -> FeatureGate {
        let original = store.checkGate(forName: gateName)

        let gate = self.statsigOptions.overrideAdapter?.getGate(user: currentUser, name: gateName, original: original) ?? original;

        if (shouldExpose) {
            logGateExposureForGate(gateName, gate: gate, isManualExposure: false)
        } else {
            logger.incrementNonExposedCheck(gateName)
        }
        if let cb = statsigOptions.evaluationCallback {
            cb(.gate(gate))
        }
        return gate
    }

    /**
     Logs an exposure event for the given gate. Only required if a related checkGateWithExposureLoggingDisabled call has been made.

     Parameters:
     - gateName: The name of the feature gate setup on console.statsig.com
     */
    public func manuallyLogGateExposure(_ gateName: String) {
        logGateExposure(gateName)
    }

    /**
     Logs an exposure event for the given feature gate. Only required if a related getFeatureGateWithExposureLoggingDisabled call has been made.

     Parameters:
     - gate: The the feature gate class of a feature gate setup on console.statsig.com
     */
    public func manuallyLogExposure(_ gate: FeatureGate) {
        logGateExposureForGate(gate.name, gate: gate, isManualExposure: true)
    }

    private func logGateExposure(_ gateName: String, gate: FeatureGate? = nil) {
        let isManualExposure = gate == nil
        let gate = gate ?? store.checkGate(forName: gateName)

        logGateExposureForGate(gateName, gate: gate, isManualExposure: isManualExposure)
    }

    private func logGateExposureForGate(_ gateName: String, gate: FeatureGate, isManualExposure: Bool) {
        let gateValue = gate.value
        let ruleID = gate.ruleID
        let dedupeKey = DedupeKey(featureGate: gate)

        logger.log(
            Event.gateExposure(
                user: currentUser,
                gateName: gateName,
                gateValue: gateValue,
                ruleID: ruleID,
                secondaryExposures: gate.secondaryExposures,
                evalDetails: gate.evaluationDetails,
                bootstrapMetadata: store.getBootstrapMetadata(),
                disableCurrentVCLogging: statsigOptions.disableCurrentVCLogging
            ).withManualExposureFlag(isManualExposure),
            exposureDedupeKey: dedupeKey
        )
    }
}


// MARK: Dynamic Configs
extension StatsigClient {
    /**
     Get the values for the given dynamic config. An exposure event will automatically be logged for the given dynamic config.

     Parameters:
     - configName: The name of the dynamic config setup on console.statsig.com

     SeeAlso [Dynamic Config Documentation](https://docs.statsig.com/dynamic-config)
     */
    public func getConfig(_ configName: String) -> DynamicConfig {
        return getConfigImpl(configName, shouldExpose: true)
    }

    /**
     Get the values for the given dynamic config. No exposure event will be logged.

     Parameters:
     - configName: The name of the dynamic config setup on console.statsig.com

     SeeAlso [Dynamic Config Documentation](https://docs.statsig.com/dynamic-config)
     */
    public func getConfigWithExposureLoggingDisabled(_ configName: String) -> DynamicConfig {
        return getConfigImpl(configName, shouldExpose: false)
    }

    private func getConfigImpl(_ configName: String, shouldExpose: Bool) -> DynamicConfig {
        let original = store.getConfig(forName: configName)

        let config = self.statsigOptions.overrideAdapter?.getDynamicConfig(
            user: currentUser,
            name: configName,
            original: original
        ) ?? original

        if (shouldExpose) {
            logConfigExposureForConfig(configName, config: config, isManualExposure: false)
        } else {
            logger.incrementNonExposedCheck(configName)
        }
        if let cb = statsigOptions.evaluationCallback {
            cb(.config(config))
        }
        return config
    }

    /**
     Logs an exposure event for the given dynamic config. Only required if a related getConfigWithExposureLoggingDisabled call has been made.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     */
    public func manuallyLogConfigExposure(_ configName: String) {
        logConfigExposure(configName)
    }

    /**
     Logs an exposure event for the given dynamic config. Only required if a related getConfigWithExposureLoggingDisabled or getExperimentWithExposureLoggingDisabled call has been made.

     Parameters:
     - config: The dynamic config class of an experiment, autotune, or dynamic config setup on console.statsig.com
     */
    public func manuallyLogExposure(_ config: DynamicConfig) {
        logConfigExposureForConfig(config.name, config: config, isManualExposure: true)
    }

    private func logConfigExposure(_ configName: String, config: DynamicConfig? = nil) {
        let isManualExposure = config == nil
        let config = config ?? store.getConfig(forName: configName)
        logConfigExposureForConfig(configName, config: config, isManualExposure: isManualExposure)
    }

    private func logConfigExposureForConfig(_ configName: String, config: DynamicConfig, isManualExposure: Bool) {
        let dedupeKey = DedupeKey(dynamicConfig: config)

        logger.log(
            Event.configExposure(
                user: currentUser,
                configName: configName,
                config: config,
                bootstrapMetadata: store.getBootstrapMetadata(),
                disableCurrentVCLogging: statsigOptions.disableCurrentVCLogging
            ).withManualExposureFlag(isManualExposure),
            exposureDedupeKey: dedupeKey
        )
    }
}


// MARK: Experiments
extension StatsigClient {
    /**
     Get the values for the given experiment or autotune. An exposure event will automatically be logged for the given experiment.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     - keepDeviceValue: Locks experiment values to the first time they are received. If an experiment changes, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Experiments Documentation](https://docs.statsig.com/experiments-plus)
     */
    public func getExperiment(_ experimentName: String, keepDeviceValue: Bool = false) -> DynamicConfig {
        return getExperimentImpl(experimentName, keepDeviceValue: keepDeviceValue, shouldExpose: true)
    }

    /**
     Get the values for the given experiment. No exposure events will be logged.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     - keepDeviceValue: Locks experiment values to the first time they are received. If an experiment changes, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Experiments Documentation](https://docs.statsig.com/experiments-plus)
     */
    public func getExperimentWithExposureLoggingDisabled(_ experimentName: String, keepDeviceValue: Bool = false) -> DynamicConfig {
        return getExperimentImpl(experimentName, keepDeviceValue: keepDeviceValue, shouldExpose: false)
    }

    private func getExperimentImpl(_ experimentName: String, keepDeviceValue: Bool, shouldExpose: Bool) -> DynamicConfig {
        let original = store.getExperiment(forName: experimentName, keepDeviceValue: keepDeviceValue)

        let experiment = self.statsigOptions.overrideAdapter?.getExperiment(
            user: currentUser,
            name: experimentName,
            original: original
        ) ?? original

        if (shouldExpose) {
            logConfigExposureForConfig(experimentName, config: experiment, isManualExposure: false)
        } else {
            logger.incrementNonExposedCheck(experimentName)
        }
        if let cb = statsigOptions.evaluationCallback {
            cb(.experiment(experiment))
        }
        return experiment
    }

    /**
     Logs an exposure event for the given experiment. Only required if a related getExperimentWithExposureLoggingDisabled has been made.

     Parameters:
     - experimentName: The name of the experiment setup on console.statsig.com
     */
    public func manuallyLogExperimentExposure(_ experimentName: String, keepDeviceValue: Bool = false) {
        logExperimentExposure(experimentName, keepDeviceValue: keepDeviceValue)
    }

    private func logExperimentExposure(_ experimentName: String, keepDeviceValue: Bool, experiment: DynamicConfig? = nil) {
        let isManualExposure = experiment == nil
        let experiment = experiment ?? store.getExperiment(forName: experimentName, keepDeviceValue: keepDeviceValue)
        logConfigExposureForConfig(experimentName, config: experiment, isManualExposure: isManualExposure)
    }
}


// MARK: Layers
extension StatsigClient {
    /**
     Get the values for the given layer. Exposure events will be fired when getValue is called on the result Layer class.

     Parameters:
     - layerName: The name of the layer setup on console.statsig.com
     - keepDeviceValue: Locks layer values to the first time they are received. If an layer values change, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Layers Documentation](https://docs.statsig.com/layers)
     */
    public func getLayer(_ layerName: String, keepDeviceValue: Bool = false) -> Layer {
        return getLayerImpl(layerName, keepDeviceValue: keepDeviceValue, shouldExpose: true)
    }

    /**
     Get the values for the given layer. No exposure events will be fired.

     Parameters:
     - layerName: The name of the layer setup on console.statsig.com
     - keepDeviceValue: Locks layer values to the first time they are received. If an layer values change, but the user has already been exposed, the original values are returned. This is not common practice.

     SeeAlso [Layers Documentation](https://docs.statsig.com/layers)
     */
    public func getLayerWithExposureLoggingDisabled(_ layerName: String, keepDeviceValue: Bool = false) -> Layer {
        return getLayerImpl(layerName, keepDeviceValue: keepDeviceValue, shouldExpose: false)
    }

    private func getLayerImpl(_ layerName: String, keepDeviceValue: Bool, shouldExpose: Bool) -> Layer {
        if (!shouldExpose) {
            logger.incrementNonExposedCheck(layerName)
        }
        let original = store.getLayer(client: shouldExpose ? self : nil, forName: layerName, keepDeviceValue: keepDeviceValue)

        let layer = self.statsigOptions.overrideAdapter?.getLayer(
            client: shouldExpose ? self : nil,
            user: currentUser,
            name: layerName,
            original: original
        ) ?? original
        if let cb = statsigOptions.evaluationCallback {
            cb(.layer(layer))
        }
        return layer
    }

    /**
     Logs an exposure event for the given layer parameter. Only required if a related getLayerWithExposureLoggingDisabled call has been made.

     Parameters:
     - layerName: The name of the layer setup on console.statsig.com
     - parameterName: The name of the parameter that was checked.
     */
    public func manuallyLogLayerParameterExposure(_ layerName: String, _ parameterName: String, keepDeviceValue: Bool = false) {
        let layer = getLayer(layerName, keepDeviceValue: keepDeviceValue)
        logLayerParameterExposureForLayer(layer, parameterName: parameterName, isManualExposure: true)
    }

    internal func logLayerParameterExposureForLayer(_ layer: Layer, parameterName: String, isManualExposure: Bool) {
        var exposures = layer.undelegatedSecondaryExposures
        var allocatedExperiment = ""
        let isExplicit = layer.explicitParameters.contains(parameterName)
        if isExplicit {
            exposures = layer.secondaryExposures
            allocatedExperiment = layer.allocatedExperimentName
        }

        let dedupeKey = DedupeKey(
            layer: layer, 
            parameterName: parameterName, 
            isExplicit: isExplicit
        )

        logger.log(
            Event.layerExposure(
                user: currentUser,
                configName: layer.name,
                ruleID: layer.ruleID,
                secondaryExposures: exposures,
                disableCurrentVCLogging: statsigOptions.disableCurrentVCLogging,
                allocatedExperimentName: allocatedExperiment,
                parameterName: parameterName,
                isExplicitParameter: isExplicit,
                evalDetails: layer.evaluationDetails,
                bootstrapMetadata: store.getBootstrapMetadata()
            ).withManualExposureFlag(isManualExposure),
            exposureDedupeKey: dedupeKey
        )
    }
}

// MARK: Parameter Stores
extension StatsigClient {
    public func getParameterStore(_ storeName: String) -> ParameterStore {
        return getParameterStoreImpl(storeName, shouldExpose: true)
    }
    
    public func getParameterStoreWithExposureLoggingDisabled(_ storeName: String) -> ParameterStore {
        return getParameterStoreImpl(storeName, shouldExpose: false)
    }
    
    private func getParameterStoreImpl(_ storeName: String, shouldExpose: Bool) -> ParameterStore {
        logger.incrementNonExposedCheck(storeName)

        let original = store.getParamStore(client: self, forName: storeName)

        var store = self.statsigOptions.overrideAdapter?.getParameterStore(
            client: self,
            name: storeName,
            original: original
        ) ?? original

        store.shouldExpose = shouldExpose
        
        if let cb = statsigOptions.evaluationCallback {
            cb(.parameterStore(store))
        }
        
        return store
    }
    
}


// MARK: Log Event
extension StatsigClient {
    /**
     Logs an event to Statsig with the provided values.

     Parameters:
     - withName: The name of the event
     - metadata: Any extra values to be logged with the event
     */
    public func logEvent(_ withName: String, metadata: [String: String]? = nil) {
        logEventImpl(withName, value: nil, metadata: metadata)
    }

    /**
     Logs an event to Statsig with the provided values.

     Parameters:
     - withName: The name of the event
     - value: A top level value for the event
     - metadata: Any extra values to be logged with the event
     */
    public func logEvent(_ withName: String, value: String, metadata: [String: String]? = nil) {
        logEventImpl(withName, value: value, metadata: metadata)
    }

    /**
     Logs an event to Statsig with the provided values.

     Parameters:
     - withName: The name of the event
     - value: A top level value for the event
     - metadata: Any extra key/value pairs to be logged with the event
     */
    public func logEvent(_ withName: String, value: Double, metadata: [String: String]? = nil) {
        logEventImpl(withName, value: value, metadata: metadata)
    }


    private func logEventImpl(_ withName: String, value: Any? = nil, metadata: [String: String]? = nil) {
        var eventName = withName

        if eventName.isEmpty {
            PrintHandler.log("[Statsig]: Must log with a non-empty event name.")
            return
        }
        if !self.statsigOptions.disableEventNameTrimming && eventName.count > maxEventNameLength {
            PrintHandler.log("[Statsig]: Event name is too long. Trimming to \(maxEventNameLength).")
            eventName = String(eventName.prefix(maxEventNameLength))
        }
        if let metadata = metadata, !JSONSerialization.isValidJSONObject(metadata) {
            PrintHandler.log("[Statsig]: metadata is not a valid JSON object. Event is logged without metadata.")
            logger.log(
                Event(
                    user: currentUser,
                    name: eventName,
                    value: value,
                    metadata: nil,
                    disableCurrentVCLogging: statsigOptions.disableCurrentVCLogging)
            )
            return
        }

        logger.log(
            Event(
                user: currentUser,
                name: eventName,
                value: value,
                metadata: metadata,
                disableCurrentVCLogging: statsigOptions.disableCurrentVCLogging)
        )
    }
}

// MARK: Local Overrides
extension StatsigClient {
    /**
     Sets a value to be returned for the given gate instead of the actual evaluated value.

     Parameters:
     - gateName: The name of the gate to be overridden
     - value: The value that will be returned
     */
    public func overrideGate(_ gateName: String, value: Bool) {
        store.overrideGate(gateName, value)
    }

    /**
     Sets a value to be returned for the given dynamic config/experiment instead of the actual evaluated value.

     Parameters:
     - configName: The name of the config or experiment to be overridden
     - value: The value that the resulting DynamicConfig will contain
     */
    public func overrideConfig(_ configName: String, value: [String: Any]) {
        store.overrideConfig(configName, value)
    }

    /**
     Sets a value to be returned for the given layer instead of the actual evaluated value.

     Parameters:
     - layerName: The name of the layer to be overridden
     - value: The value that the resulting Layer will contain
     */
    public func overrideLayer(_ layerName: String, value: [String: Any]) {
        store.overrideLayer(layerName, value)
    }

    /**
     Sets a value to be returned for the given parameter store instead of following the actual ref in the store.

     Parameters:
     - storeName: The name of the config or experiment to be overridden
     - value: Dictionary where keys are property names and values are static ref values in the overridden store
     */
    public func overrideParamStore(_ storeName: String, value: [String: Any]) {
        store.overrideParamStore(storeName, value)
    }

    /**
     Clears any overridden value for the given gate/dynamic config/experiment.

     Parameters:
     - name: The name of the gate/dynamic config/experiment to clear
     */
    public func removeOverride(_ name: String) {
        store.removeOverride(name)
    }

    /**
     Clears all overriden values.
     */
    public func removeAllOverrides() {
        store.removeAllOverrides()
    }

    /**
     Returns all values that are currently overriden.
     */
    public func getAllOverrides() -> StatsigOverrides {
        return store.getAllOverrides()
    }
}


// MARK: Debug View
extension StatsigClient {
    /**
     Presents a view of the current internal state of the SDK.
     */
    public func openDebugView(_ callback: DebuggerCallback? = nil) {
        ensureMainThread { [weak self] in
            if let self = self {
                StatsigDebugViewController.show(self.sdkKey, self.getDebugViewControllerState(), callback)
            }
        }
    }

    /**
     Creates a view controller with the current internal state of the SDK.
     */
    public func createDebugViewController(_ callback: DebuggerCallback? = nil) -> StatsigDebugViewController? {
        return StatsigDebugViewController(sdkKey: self.sdkKey, state: self.getDebugViewControllerState(), callback: callback)
    }

    private func getDebugViewControllerState() -> [String: Any?] {
        let cache = store.cache
        let reason = cache.getEvaluationDetails().getDetailedReason()
        return [
            "user": self.currentUser.toDictionary(forLogging: false),
            "gates": cache.gates,
            "configs": cache.configs,
            "layers": cache.layers,
            "evalReason": reason
        ]
    }
}


// MARK: Misc Private
extension StatsigClient {

    internal func fetchValuesFromNetwork(
        user: StatsigUser,
        marker: NetworkMarker? = nil,
        processMarker: InitializeStepMarker? = nil,
        storeMarker: InitializeStepMarker? = nil,
        completion: ResultCompletionBlock?
    ) {
        let currentUser = user
        storeMarker?.start()
        let initValues = self.store.getInitializationValues(user: currentUser)
        storeMarker?.end(success: true)

        networkService.fetchInitialValues(
            for: currentUser,
            sinceTime: initValues.lastUpdateTime,
            previousDerivedFields: initValues.previousDerivedFields,
            fullChecksum: initValues.fullChecksum,
            marker: marker,
            processMarker: processMarker
        ) { [weak self] error in
            if let self = self {
                if let error = error {
                    self.logger.log(Event.statsigInternalEvent(
                        user: user,
                        name: "fetch_values_failed",
                        value: nil,
                        metadata: ["error": error.message]))
                }
            }

            completion?(error)
        }
    }

    private func scheduleRepeatingSync() {
        syncTimer?.invalidate()

        let timer = Timer(
            timeInterval: self.statsigOptions.autoValueUpdateIntervalSec,
            repeats: true,
            block: { [weak self] _ in
            self?.syncValuesForCurrentUser()
        })
        syncTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    private func syncValuesForCurrentUser() {
        let initValues = self.store.getInitializationValues(user: currentUser)

        self.networkService.fetchUpdatedValues(
            for: currentUser,
            lastSyncTimeForUser: initValues.lastUpdateTime,
            previousDerivedFields: initValues.previousDerivedFields,
            fullChecksum: initValues.fullChecksum) { [weak self] error in
                self?.notifyOnUserUpdatedListeners(error)
            }
    }

    private static func normalizeUser(_ user: StatsigUser?, options: StatsigOptions?) -> StatsigUser {
        var normalized = user ?? StatsigUser()
        if let validationCallback = options?.userValidationCallback {
            normalized = validationCallback(normalized)
        }
        normalized.statsigEnvironment = options?.environment ?? [:]
        if let stableID = options?.overrideStableID {
            normalized.setStableID(stableID)
        }
        return normalized
    }

    private func updateUserImpl(_ user: StatsigUser, values: [String: Any]? = nil, completion: ResultCompletionBlock? = nil) {
        let normalizedUser = StatsigClient.normalizeUser(user, options: statsigOptions)
        currentUser = normalizedUser
        store.updateUser(currentUser, values: values)
        logger.user = currentUser
        
        if values != nil {
            completion?(nil)
            return
        }
        
        ensureMainThread { [weak self] in
            self?.fetchValuesFromNetwork(user: normalizedUser) { [weak self, completion] error in
                guard let self = self else {
                    return
                }
                
                if self.statsigOptions.enableAutoValueUpdate {
                    self.scheduleRepeatingSync()
                }
                
                self.notifyOnUserUpdatedListeners(error)
                completion?(error)
            }
        }
    }

    private func notifyOnInitializedListeners(_ error: StatsigClientError?) {
        for getter in listeners {
            if let listener = getter() {
                listener.onInitializedWithResult?(error)
                // We use this cast to work around a deprecation warning we added on `onInitialized`
                (listener as StatsigListeningInternal).onInitialized?(error?.message)
            }
        }
    }

    private func notifyOnUserUpdatedListeners(_ error: StatsigClientError?) {
        for getter in listeners {
            if let listener = getter() {
                listener.onUserUpdatedWithResult?(error)
                // We use this cast to work around a deprecation warning we added on `onUserUpdated`
                (listener as StatsigListeningInternal).onUserUpdated?(error?.message)
            }
        }
    }
}

// MARK: Deprecated
extension StatsigClient {
    /**
     Switches the user and pulls new values for that user from Statsig.
     Default values will be returned until the update is complete.

     Parameters:
     - user: The new user
     - completion: A callback block called when the new values have been received. May be called with an error message string if the fetch fails.
     */
    @available(*, deprecated, message: "Use `StatsigClient.updateUserWithResult` instead")
    public func updateUser(_ user: StatsigUser, values: [String: Any]? = nil, completion: completionBlock = nil) {
        self.logger.clearExposuresDedupeDict()

        self.updateUserImpl(user, values: values) { error in 
            completion?(error?.message)
        }
    }
    
    /**
     Manually triggered the refreshing process for the current user

     Parameters:
     - completion: A callback block called when the new values/update operation have been received. May be called with an error message string if the fetch fails.
     */
    @available(*, deprecated, message: "Use `StatsigClient.refreshCacheWithResult` instead")
    public func refreshCache(_ completion: completionBlock = nil) {
        self.updateUser(self.currentUser, completion: completion)
    }
    
    public func getEvaluationSource() -> EvaluationSource {
        return store.getEvaluationSource()
    }
}
