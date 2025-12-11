internal enum DedupeKey: Hashable {
    case featureGate(
        name: String,
        value: Bool,
        ruleID: String,
        evaluation: EvaluationDetails.DedupeKey
    )

    case dynamicConfig(
        configName: String,
        ruleID: String,
        evaluation: EvaluationDetails.DedupeKey
    )

    case layerParameter(
        layerName: String,
        ruleID: String,
        allocatedExperiment: String,
        parameterName: String,
        isExplicit: Bool,
        evaluation: EvaluationDetails.DedupeKey
    )

    init(featureGate: FeatureGate) {
        self = .featureGate(
            name: featureGate.name,
            value: featureGate.value,
            ruleID: featureGate.ruleID,
            evaluation: featureGate.evaluationDetails.dedupeKey
        )
    }

    init(dynamicConfig: DynamicConfig) {
        self = .dynamicConfig(
            configName: dynamicConfig.name,
            ruleID: dynamicConfig.ruleID,
            evaluation: dynamicConfig.evaluationDetails.dedupeKey
        )
    }

    init(layer: Layer, parameterName: String, isExplicit: Bool) {
        self = .layerParameter(
            layerName: layer.name,
            ruleID: layer.ruleID,
            allocatedExperiment: layer.allocatedExperimentName,
            parameterName: parameterName,
            isExplicit: isExplicit,
            evaluation: layer.evaluationDetails.dedupeKey
        )
    }
}
