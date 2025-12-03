import Foundation

public enum StatsigOnDeviceEvalAdapterError: Error {
    case failedToParseSpecsValue
}

public class OnDeviceEvalAdapter: OverrideAdapter {

    private var evaluator: Evaluator

    internal init(lcut: UInt64, specs: SpecMap, paramStores: [String : ParamStoreSpec]?) {
        self.evaluator = Evaluator(lcut: lcut, specs: specs, paramStores: paramStores)
    }

    public convenience init?(stringPayload: String) {
        self.init(parseResult: parseSpecs(string: stringPayload))
    }

    public convenience init?(data: Data) {
        self.init(parseResult: parseSpecs(data: data))
    }

    private convenience init?(parseResult: Result<SpecsResponse, Error>) {
        let dcsResponse: SpecsResponse
        switch parseResult {
            case .failure(let error):
                PrintHandler.log("[Statsig] OnDeviceEvalAdapter failed to parse specs: \(error)")
                return nil
            case .success(let value):
                dcsResponse = value
        }

        let specs: SpecMap = [
            .gate: createMapFromList(list: dcsResponse.featureGates, key: \.name),
            .config: createMapFromList(list: dcsResponse.dynamicConfigs, key: \.name),
            .layer: createMapFromList(list: dcsResponse.layerConfigs, key: \.name)
        ]

        self.init(lcut: dcsResponse.time, specs: specs, paramStores: dcsResponse.paramStores)
    }

    func getGate(user: StatsigUser, name: String, original: FeatureGate) -> FeatureGate?
    {
        return decideConfigBase(original, evaluator.getGate(user, name))
    }

    func getDynamicConfig(user: StatsigUser, name: String, original: DynamicConfig) -> DynamicConfig?
    {
        return decideConfigBase(original, evaluator.getDynamicConfig(user, name))
    }

    func getExperiment(user: StatsigUser, name: String, original: DynamicConfig) -> DynamicConfig? {
        return decideConfigBase(original, evaluator.getExperiment(user, name))
    }

    func getLayer(client: StatsigClient?, user: StatsigUser, name: String, original: Layer) -> Layer? {
        return decideConfigBase(original, evaluator.getLayer(client, user, name))
    }

    func getParameterStore(client: StatsigClient?, name: String, original: ParameterStore) -> ParameterStore? {
        return decideConfigBase(original, evaluator.getParameterStore(name, client))
    }

    private func decideConfigBase<T>(_ originalConfig: T, _ overriddenConfig: T?) -> T? where T : ConfigBase {
        guard let overriddenConfig = overriddenConfig,
            let overriddenConfigLcut = overriddenConfig.evaluationDetails.lcut else {
            return nil
        }

        guard let originalConfigLcut = originalConfig.evaluationDetails.lcut else {
            return overriddenConfig
        }

        return overriddenConfigLcut <= originalConfigLcut ? nil : overriddenConfig
    }
}

func createMapFromList<T, V>(list: [T], key: KeyPath<T, V>) -> [V: T] where V: Hashable {
    var map: [V: T] = [:]
    for item in list {
        let keyValue = item[keyPath: key]
        map[keyValue] = item
    }
    return map
}
