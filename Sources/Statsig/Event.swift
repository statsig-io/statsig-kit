import Foundation

class Event {
    let name: String
    let value: Any?
    let metadata: [String: Any]?
    let time: UInt64
    let userData: [String: Any?]
    let secondaryExposures: [[String: String]]?
    var statsigMetadata: [String: String]?
    var allocatedExperimentHash: String?
    var isManualExposure: Bool = false

    static let statsigPrefix = "statsig::"
    static let configExposureEventName = "config_exposure"
    static let layerExposureEventName = "layer_exposure"
    static let gateExposureEventName = "gate_exposure"
    static let currentVCKey = "currentPage"

    init(
        user: StatsigUser?,
        name: String,
        value: Any? = nil,
        metadata: [String: Any]? = nil,
        secondaryExposures: [[String: String]]? = nil,
        disableCurrentVCLogging: Bool
    ) {
        self.time = Time.now()
        self.userData = user?.toDictionary(forLogging: true) ?? [:]
        self.name = name
        self.value = value
        self.metadata = metadata
        self.secondaryExposures = secondaryExposures

        if !disableCurrentVCLogging {
            PlatformCompatibility.getRootViewControllerClassName { name in
                if let name = name {
                    self.statsigMetadata = [Event.currentVCKey: "\(name)"]
                }
            }
        }
    }

    func withManualExposureFlag(_ isManualExposure: Bool) -> Event {
        self.isManualExposure = isManualExposure
        return self
    }

    static func statsigInternalEvent(
        user: StatsigUser?,
        name: String,
        value: Any? = nil,
        metadata: [String: Any]? = nil,
        secondaryExposures: [[String: String]]? = nil,
        disableCurrentVCLogging: Bool = true  // for internal events, default to not log the VC, other than for exposures
    ) -> Event {
        return Event(
            user: user,
            name: statsigPrefix + name,
            value: value,
            metadata: metadata,
            secondaryExposures: secondaryExposures,
            disableCurrentVCLogging: disableCurrentVCLogging
        )
    }

    static func gateExposure(
        user: StatsigUser,
        gateName: String,
        gateValue: Bool,
        ruleID: String,
        secondaryExposures: [[String: String]],
        evalDetails: EvaluationDetails,
        bootstrapMetadata: BootstrapMetadata?,
        disableCurrentVCLogging: Bool
    ) -> Event {
        var metadata: [String: Any] = [
            "gate": gateName,
            "gateValue": String(gateValue),
            "ruleID": ruleID,
        ]

        if let bootstrapMetadata = bootstrapMetadata {
            metadata["bootstrapMetadata"] = bootstrapMetadata.toDictionary()
        }

        evalDetails.addToDictionary(&metadata)

        return statsigInternalEvent(
            user: user,
            name: gateExposureEventName,
            value: nil,
            metadata: metadata,
            secondaryExposures: secondaryExposures,
            disableCurrentVCLogging: disableCurrentVCLogging
        )
    }

    static func configExposure(
        user: StatsigUser,
        configName: String,
        config: DynamicConfig,
        bootstrapMetadata: BootstrapMetadata?,
        disableCurrentVCLogging: Bool
    ) -> Event {
        let ruleID = config.ruleID
        let secondaryExposures = config.secondaryExposures
        let evalDetails = config.evaluationDetails

        var metadata: [String: Any] = [
            "config": configName,
            "ruleID": ruleID,
        ]

        if let bootstrapMetadata = bootstrapMetadata {
            metadata["bootstrapMetadata"] = bootstrapMetadata.toDictionary()
        }

        metadata["rulePassed"] = config.didPassRule ? "true" : "false"

        evalDetails.addToDictionary(&metadata)

        return statsigInternalEvent(
            user: user,
            name: configExposureEventName,
            value: nil,
            metadata: metadata,
            secondaryExposures: secondaryExposures,
            disableCurrentVCLogging: disableCurrentVCLogging
        )
    }

    static func layerExposure(
        user: StatsigUser,
        configName: String,
        ruleID: String,
        secondaryExposures: [[String: String]],
        disableCurrentVCLogging: Bool,
        allocatedExperimentName: String,
        parameterName: String,
        isExplicitParameter: Bool,
        evalDetails: EvaluationDetails,
        bootstrapMetadata: BootstrapMetadata?
    ) -> Event {
        var metadata: [String: Any] = [
            "config": configName,
            "ruleID": ruleID,
            "allocatedExperiment": allocatedExperimentName,
            "parameterName": parameterName,
            "isExplicitParameter": "\(isExplicitParameter)",
        ]

        if let bootstrapMetadata = bootstrapMetadata {
            metadata["bootstrapMetadata"] = bootstrapMetadata.toDictionary()
        }

        evalDetails.addToDictionary(&metadata)

        return statsigInternalEvent(
            user: user,
            name: layerExposureEventName,
            value: nil,
            metadata: metadata,
            secondaryExposures: secondaryExposures,
            disableCurrentVCLogging: disableCurrentVCLogging
        )
    }

    func toDictionary() -> [String: Any] {
        var metadataForLogging = metadata
        if isManualExposure {
            metadataForLogging = metadataForLogging ?? [:]
            metadataForLogging?["isManualExposure"] = "true"
        }

        return [
            "eventName": name,
            "user": userData,
            "time": time,
            "value": value,
            "metadata": metadataForLogging,
            "statsigMetadata": statsigMetadata,
            "secondaryExposures": secondaryExposures,
            "allocatedExperimentHash": allocatedExperimentHash,
        ].compactMapValues { $0 }
    }
}
