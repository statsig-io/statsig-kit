import Foundation

typealias ParamStoreConfiguration = [String: [String: Any]]

fileprivate struct RefType {
    static let staticValue = "static"
    static let gate = "gate"
    static let dynamicConfig = "dynamic_config"
    static let experiment = "experiment"
    static let layer = "layer"
}

fileprivate struct ParamKeys {
    static let paramType = "param_type"
    static let refType = "ref_type"

    // Gate
    static let gateName = "gate_name"
    static let passValue = "pass_value"
    static let failValue = "fail_value"

    // Static Value
    static let value = "value"

    // Dynamic Config / Experiment / Layer
    static let paramName = "param_name"
    static let configName = "config_name"
    static let experimentName = "experiment_name"
    static let layerName = "layer_name"
}

public struct ParameterStore: ConfigBase {
    /**
     The name used to retrieve this ParameterStore.
     */
    public let name: String

    /**
     (For debug purposes) Why did Statsig return this ParameterStore
     */
    public let evaluationDetails: EvaluationDetails

    internal let configuration: ParamStoreConfiguration
    weak internal var client: StatsigClient?
    internal var shouldExpose = true

    public var keys: [String: [String: Any]].Keys {
        return configuration.keys
    }

    internal init(
        name: String,
        evaluationDetails: EvaluationDetails,
        client: StatsigClient? = nil,
        configuration: [String: Any] = [:]
    ) {
        self.name = name
        self.evaluationDetails = evaluationDetails
        self.client = client
        self.configuration = configuration as? ParamStoreConfiguration ?? ParamStoreConfiguration()
    }

    /**
     Get the value for the given key. If the value cannot be found, or is found to have a different type than the defaultValue, the defaultValue will be returned.
     If a valid value is found, a layer exposure event will be fired.

     Parameters:
     - forKey: The key of parameter being fetched
     - defaultValue: The fallback value if the key cannot be found
     */
    public func getValue<T: StatsigDynamicConfigValue>(forKey key: String, defaultValue: T) -> T {
        return getValueImpl(forKey: key, defaultValue: defaultValue) ?? defaultValue
    }

    /**
     Get the value for the given key, falling back to nil if it cannot be found or is of a different type.
     If you get the error "Generic parameter 'T' could not be inferred", here are a few ways to fix it:
     1. Set the type on the variable definition `let a: String? = layer.getValue(...)`
     2. Cast to the type you need `let a = layer.getValue(...) as String?`
     3. Add the defaultValue parameter: `let a = layer.getValue(forKey:"key", defaultValue: "")`.

     Parameters:
     - forKey: The key of parameter being fetched
     */
    public func getValue<T: StatsigDynamicConfigValue>(forKey key: String) -> T? {
        return getValueImpl(forKey: key)
    }

    public func getValueImpl<T: StatsigDynamicConfigValue>(
        forKey paramName: String,
        defaultValue: T? = nil
    ) -> T? {
        if configuration.isEmpty {
            return defaultValue
        }

        let expectedType =
            if let defaultValue = defaultValue {
                getTypeOf(defaultValue)
            } else {
                getTypeOf(type: T.self)
            }

        guard
            let client = client,
            let param = configuration[paramName],
            let refType = param[ParamKeys.refType] as? String,
            let paramType = param[ParamKeys.paramType] as? String,
            expectedType == paramType
        else {
            return defaultValue
        }

        switch refType {
        case RefType.staticValue:
            return getMappedStaticValue(param)

        case RefType.gate:
            return getMappedGateValue(client, param)

        case RefType.dynamicConfig:
            return getMappedDynamicConfigValue(client, param, defaultValue)

        case RefType.experiment:
            return getMappedExperimentValue(client, param, defaultValue)

        case RefType.layer:
            return getMappedLayerValue(client, param, defaultValue)

        default:
            return defaultValue
        }
    }

    fileprivate func getMappedStaticValue<T>(
        _ param: [String: Any]
    ) -> T? {
        return param[ParamKeys.value] as? T
    }

    fileprivate func getMappedGateValue<T: StatsigDynamicConfigValue>(
        _ client: StatsigClient,
        _ param: [String: Any]
    ) -> T? {
        guard
            let gateName = param[ParamKeys.gateName] as? String,
            let passValue = param[ParamKeys.passValue] as? T,
            let failValue = param[ParamKeys.failValue] as? T
        else {
            return nil
        }

        let gate =
            shouldExpose
            ? client.getFeatureGate(gateName)
            : client.getFeatureGateWithExposureLoggingDisabled(gateName)
        return gate.value ? passValue : failValue
    }

    fileprivate func getMappedDynamicConfigValue<T: StatsigDynamicConfigValue>(
        _ client: StatsigClient,
        _ param: [String: Any],
        _ defaultValue: T?
    ) -> T? {
        guard
            let configName = param[ParamKeys.configName] as? String,
            let paramName = param[ParamKeys.paramName] as? String
        else {
            return defaultValue
        }

        let config =
            shouldExpose
            ? client.getConfig(configName)
            : client.getConfigWithExposureLoggingDisabled(configName)
        return config.getValueImpl(forKey: paramName, defaultValue: defaultValue)
    }

    fileprivate func getMappedExperimentValue<T: StatsigDynamicConfigValue>(
        _ client: StatsigClient,
        _ param: [String: Any],
        _ defaultValue: T?
    ) -> T? {
        guard
            let experimentName = param[ParamKeys.experimentName] as? String,
            let paramName = param[ParamKeys.paramName] as? String
        else {
            return defaultValue
        }

        let experiment =
            shouldExpose
            ? client.getExperiment(experimentName)
            : client.getExperimentWithExposureLoggingDisabled(experimentName)
        return experiment.getValueImpl(forKey: paramName, defaultValue: defaultValue)
    }

    fileprivate func getMappedLayerValue<T: StatsigDynamicConfigValue>(
        _ client: StatsigClient,
        _ param: [String: Any],
        _ defaultValue: T?
    ) -> T? {
        guard
            let layerName = param[ParamKeys.layerName] as? String,
            let paramName = param[ParamKeys.paramName] as? String
        else {
            return defaultValue
        }

        let layer =
            shouldExpose
            ? client.getLayer(layerName)
            : client.getLayerWithExposureLoggingDisabled(layerName)
        return layer.getValueImpl(forKey: paramName, defaultValue: defaultValue)
    }

}
