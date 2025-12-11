import CommonCrypto
import Foundation

class Evaluator {

    private var lcut: UInt64
    private var specs: SpecMap = [:]
    private var paramStores: [String: ParamStoreSpec]?
    private var receivedAt: UInt64 = Time.now()

    internal init(
        lcut: UInt64,
        specs: SpecMap,
        paramStores: [String: ParamStoreSpec]?
    ) {
        self.lcut = lcut
        self.specs = specs
        self.paramStores = paramStores
    }

    func getGate(_ user: StatsigUser, _ name: String) -> FeatureGate? {
        guard let spec: Spec = getSpec(.gate, name) else {
            return .empty(name, self.evalDetails(reason: .Unrecognized))
        }

        let evaluationResult = evaluateSpec(spec, user)
        return FeatureGate(
            name: name,
            value: evaluationResult.boolValue,
            ruleID: evaluationResult.ruleID,
            evalDetails: self.evalDetails(reason: .Recognized),
            secondaryExposures: evaluationResult.secondaryExposures
        )
    }

    func getDynamicConfig(_ user: StatsigUser, _ name: String) -> DynamicConfig? {
        guard let spec: Spec = getSpec(.config, name) else {
            return .empty(name, self.evalDetails(reason: .Unrecognized))
        }

        let evaluationResult = evaluateSpec(spec, user)
        return DynamicConfig(
            configName: name,
            value: evaluationResult.jsonValue?.getSerializedDictionaryResult()?.dictionary ?? [:],
            ruleID: evaluationResult.ruleID,
            evalDetails: self.evalDetails(reason: .Recognized),
            secondaryExposures: evaluationResult.secondaryExposures,
            isExperimentActive: evaluationResult.isExperimentActive,
            isUserInExperiment: evaluationResult.isExperimentGroup,
            didPassRule: evaluationResult.boolValue
        )
    }

    func getExperiment(_ user: StatsigUser, _ name: String) -> DynamicConfig? {
        guard let spec: Spec = getSpec(.config, name) else {
            return .empty(name, self.evalDetails(reason: .Unrecognized))
        }

        let evaluationResult = evaluateSpec(spec, user)
        return DynamicConfig(
            configName: name,
            value: evaluationResult.jsonValue?.getSerializedDictionaryResult()?.dictionary ?? [:],
            ruleID: evaluationResult.ruleID,
            evalDetails: self.evalDetails(reason: .Recognized),
            secondaryExposures: evaluationResult.secondaryExposures,
            isExperimentActive: evaluationResult.isExperimentActive,
            isUserInExperiment: evaluationResult.isExperimentGroup,
            didPassRule: evaluationResult.boolValue
        )
    }

    func getLayer(_ client: StatsigClient?, _ user: StatsigUser, _ name: String) -> Layer? {
        guard let spec = getSpec(.layer, name) else {
            return .empty(client, name, self.evalDetails(reason: .Unrecognized))
        }

        let evaluationResult = evaluateSpec(spec, user)
        return Layer(
            client: client,
            name: name,
            value: evaluationResult.jsonValue?.getSerializedDictionaryResult()?.dictionary ?? [:],
            ruleID: evaluationResult.ruleID,
            groupName: evaluationResult.groupName,
            evalDetails: self.evalDetails(reason: .Recognized),
            secondaryExposures: evaluationResult.secondaryExposures,
            undelegatedSecondaryExposures: evaluationResult.undelegatedSecondaryExposures,
            explicitParameters: Set(evaluationResult.explicitParameters ?? []),
            allocatedExperimentName: evaluationResult.configDelegate,
            isExperimentActive: evaluationResult.isExperimentActive,
            isUserInExperiment: evaluationResult.isExperimentGroup
        )
    }

    func getParameterStore(_ name: String, _ client: StatsigClient?) -> ParameterStore? {
        let paramStore = self.paramStores?[name]

        return ParameterStore(
            name: name,
            evaluationDetails: self.evalDetails(
                reason: paramStore != nil ? .Recognized : .Unrecognized),
            client: client,
            configuration: paramStore?.parameters.getSerializedDictionaryResult()?.dictionary ?? [:]
        )
    }

    // MARK: Evaluation

    private func evalDetails(reason: EvaluationReason) -> EvaluationDetails {
        return EvaluationDetails(
            source: .Bootstrap, reason: reason, lcut: self.lcut, receivedAt: self.receivedAt,
            prefix: "[OnDevice]")
    }

    private func getSpec(_ type: SpecType, _ name: String) -> Spec? {
        return specs[type]?[name]
    }

    private func evaluateSpec(_ spec: Spec, _ user: StatsigUser) -> EvaluationResult {
        guard spec.enabled else {
            return .disabled(spec.defaultValue)
        }

        var exposures = [[String: String]]()

        for rule in spec.rules {
            let result = evaluateRule(rule, user)

            if result.unsupported {
                return result
            }

            if let resultExposures = result.secondaryExposures {
                exposures.append(contentsOf: resultExposures)
            }

            if !result.boolValue {
                continue
            }

            if let delegatedResult = evaluateDelegate(rule, user, exposures) {
                return delegatedResult
            }

            let pass = evaluatePassPercentage(rule, spec.salt, user)
            return .specResult(
                ruleID: result.ruleID,
                boolValue: pass,
                jsonValue: pass ? result.jsonValue : spec.defaultValue,
                secondaryExposures: exposures,
                isExperimentGroup: result.isExperimentGroup,
                groupName: result.groupName,
                version: spec.version,
                isExperimentActive: spec.isActive
            )
        }

        return .specDefaultResult(
            jsonValue: spec.defaultValue,
            secondaryExposures: exposures,
            version: spec.version
        )
    }

    private func evaluateRule(_ rule: SpecRule, _ user: StatsigUser) -> EvaluationResult {
        var exposures = [[String: String]]()
        var pass = true

        for condition in rule.conditions {
            let result = evaluateCondition(condition, user)

            if result.unsupported {
                return result
            }

            if let resultExposures = result.secondaryExposures {
                exposures.append(contentsOf: resultExposures)
            }

            if !result.boolValue {
                pass = false
            }
        }

        return .ruleResult(
            ruleID: rule.id,
            boolValue: pass,
            jsonValue: rule.returnValue,
            secondaryExposures: exposures,
            isExperimentGroup: rule.isExperimentGroup ?? false,
            groupName: rule.groupName
        )
    }

    private func evaluateDelegate(
        _ rule: SpecRule,
        _ user: StatsigUser,
        _ exposures: [[String: String]]
    ) -> EvaluationResult? {
        guard let delegate = rule.configDelegate else {
            return nil
        }

        guard let spec = getSpec(.config, delegate) else {
            return nil
        }

        let result = evaluateSpec(spec, user)
        return .delegated(
            base: result,
            delegate: delegate,
            explicitParameters: spec.explicitParameters,
            secondaryExposures: exposures + (result.secondaryExposures ?? []),
            undelegatedSecondaryExposures: exposures,
            isExperimentActive: spec.isActive
        )
    }

    private func evaluateCondition(_ condition: SpecCondition, _ user: StatsigUser)
        -> EvaluationResult
    {
        var value: JsonValue? = nil
        var pass = false

        let field = condition.field
        let target = condition.targetValue
        let idType = condition.idType
        let type = condition.type.lowercased()

        switch type {
        case "public":
            return .boolean(true)

        case "pass_gate", "fail_gate":
            let result = evaluateNestedGate(
                target?.asString() ?? "",
                user
            )

            return .boolean(
                type == "fail_gate" ? !result.boolValue : result.boolValue,
                result.secondaryExposures
            )

        case "multi_pass_gate", "multi_fail_gate":
            guard let gates = target?.asJsonArray() else {
                return getUnsupportedResult(type)
            }

            return evaluateNestedGates(gates, type, user)

        case "user_field", "ip_based", "ua_based":
            value = user.getUserValue(field)
            break

        case "environment_field":
            value = user.getFromEnvironment(field)
            break

        case "current_time":
            value = .int(Int64(Date().timeIntervalSince1970 * 1000))
            break

        case "user_bucket":
            let hash = getHashForUserBucket(condition, user) % 1000
            value = .int(Int64(hash))
            break

        case "unit_id":
            if let unitID = user.getUnitID(idType) {
                value = .string(unitID)
            }
            break

        default:
            return getUnsupportedResult(condition.type.lowercased())
        }

        let op = condition.operator?.lowercased()
        switch op {

        case "gt", "gte", "lt", "lte":
            pass = Comparison.numbers(value, target, op)

        case "version_gt", "version_gte",
            "version_lt", "version_lte",
            "version_eq", "version_neq":
            pass = Comparison.versions(value, target, op)

        case "any", "none",
            "str_starts_with_any", "str_ends_with_any",
            "str_contains_any", "str_contains_none":
            pass = Comparison.stringInArray(value, target, op, ignoreCase: true)

        case "any_case_sensitive", "none_case_sensitive":
            pass = Comparison.stringInArray(value, target, op, ignoreCase: false)

        case "str_matches":
            pass = Comparison.stringWithRegex(value, target)

        case "before", "after", "on":
            pass = Comparison.time(value, target, op)

        case "eq":
            pass = value == target

        case "neq":
            pass = value != target

        case "in_segment_list":
            return getUnsupportedResult("in_segment_list")
        case "not_in_segment_list":
            return getUnsupportedResult("not_in_segment_list")

        default:
            return getUnsupportedResult("Operator Was Null")
        }

        return .boolean(pass)
    }

    private func evaluateNestedGates(
        _ gateNames: [JsonValue],
        _ type: String,
        _ user: StatsigUser
    ) -> EvaluationResult {
        let isMultiPassGateType = type == "multi_pass_gate"
        var exposures = [[String: String]]()
        var pass = false

        for name in gateNames {
            guard let name = name.asString() else {
                return getUnsupportedResult("Expected gate name to be string.")
            }

            let result = evaluateNestedGate(name, user)
            if result.unsupported {
                return result
            }

            if let resultExposures = result.secondaryExposures {
                exposures.append(contentsOf: resultExposures)
            }

            if isMultiPassGateType == result.boolValue {
                pass = true
                break
            }
        }

        return .boolean(
            pass,
            exposures
        )
    }

    private func evaluateNestedGate(
        _ gateName: String,
        _ user: StatsigUser
    ) -> EvaluationResult {
        var exposures = [[String: String]]()
        var gateResult: EvaluationResult? = nil

        if let gateSpec = getSpec(.gate, gateName) {
            gateResult = evaluateSpec(gateSpec, user)
        }

        exposures.append(contentsOf: gateResult?.secondaryExposures ?? [])
        if !gateName.hasPrefix("segment:") {
            exposures.append([
                "gate": gateName,
                "gateValue": String(gateResult?.boolValue ?? false),
                "ruleID": gateResult?.ruleID ?? "",
            ])
        }

        return .boolean(
            gateResult?.boolValue ?? false,
            exposures
        )
    }

    private func evaluatePassPercentage(
        _ rule: SpecRule,
        _ specSalt: String,
        _ user: StatsigUser
    ) -> Bool {
        let unitID = user.getUnitID(rule.idType) ?? ""
        let hash = computeUserHash("\(specSalt).\(rule.salt).\(unitID)")
        return Double(hash % 10_000) < (rule.passPercentage * 100.0)
    }

    private func getHashForUserBucket(_ condition: SpecCondition, _ user: StatsigUser) -> UInt64 {
        let unitID = user.getUnitID(condition.idType) ?? ""
        let salt = condition.additionalValues?["salt"]?.asString() ?? ""
        let hash = computeUserHash("\(salt).\(unitID)")
        return hash % 1000
    }

    private func computeUserHash(_ value: String) -> UInt64 {
        let data = value.utf8
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        _ = data.withContiguousStorageIfAvailable { buffer in
            if let baseAddress = buffer.baseAddress {
                _ = CC_SHA256(baseAddress, CC_LONG(data.count), &digest)
            }
        }

        let uint64Value = digest.prefix(MemoryLayout<UInt64>.size).reduce(UInt64(0)) {
            $0 << 8 | UInt64($1)
        }

        return uint64Value
    }

    func getUnsupportedResult(_ reason: String) -> EvaluationResult {
        return .unsupported(reason)
    }
}
