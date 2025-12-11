import Foundation

protocol OverrideAdapter {
    func getGate(user: StatsigUser, name: String, original: FeatureGate) -> FeatureGate?
    func getDynamicConfig(user: StatsigUser, name: String, original: DynamicConfig)
        -> DynamicConfig?
    func getExperiment(user: StatsigUser, name: String, original: DynamicConfig) -> DynamicConfig?
    func getLayer(client: StatsigClient?, user: StatsigUser, name: String, original: Layer)
        -> Layer?
    func getParameterStore(client: StatsigClient?, name: String, original: ParameterStore)
        -> ParameterStore?
}
