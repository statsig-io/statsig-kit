public struct FeatureGate: ConfigBase, Codable {
    public let name: String
    public let ruleID: String
    public let value: Bool
    public let secondaryExposures: [[String: String]]
    public let evaluationDetails: EvaluationDetails

    internal init(name: String, gateObj: [String: Any], evalDetails: EvaluationDetails) {
        self.name = name
        self.value = gateObj["value"] as? Bool ?? false
        self.ruleID = gateObj["rule_id"] as? String ?? ""
        self.secondaryExposures = gateObj["secondary_exposures"] as? [[String: String]] ?? []
        self.evaluationDetails = evalDetails
    }

    internal init(
        name: String, value: Bool, ruleID: String, evalDetails: EvaluationDetails,
        secondaryExposures: [[String: String]]? = nil
    ) {
        self.name = name
        self.value = value
        self.ruleID = ruleID
        self.secondaryExposures = secondaryExposures ?? []
        self.evaluationDetails = evalDetails
    }

    internal static func empty(
        _ name: String,
        _ evalDetails: EvaluationDetails
    ) -> FeatureGate {
        return FeatureGate(
            name: name,
            value: false,
            ruleID: "",
            evalDetails: evalDetails,
            secondaryExposures: []
        )
    }
}
