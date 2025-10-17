import Foundation

@objc(StatsigOptions)
public final class StatsigOptionsObjC: NSObject {
    var optionsInternal: StatsigOptions

    @objc public init(args: [String: Any]) {
        let environment = args["environment"] as? StatsigEnvironment
        self.optionsInternal = StatsigOptions(environment: environment)

        if let initTimeout = args["initTimeout"] as? Double {
            self.optionsInternal.initTimeout = initTimeout
        }

        if let disableCurrentVCLogging = args["disableCurrentVCLogging"] as? Bool {
            self.optionsInternal.disableCurrentVCLogging = disableCurrentVCLogging
        }

        if let enableAutoValueUpdate = args["enableAutoValueUpdate"] as? Bool {
            self.optionsInternal.enableAutoValueUpdate = enableAutoValueUpdate
        }

        if let overrideStableID = args["overrideStableID"] as? String {
            self.optionsInternal.overrideStableID = overrideStableID
        }

        if let eventLoggingEnabled = args["eventLoggingEnabled"] as? Bool {
            self.optionsInternal.eventLoggingEnabled = eventLoggingEnabled
        }

        if let disableDiagnostics = args["disableDiagnostics"] as? Bool {
            self.optionsInternal.disableDiagnostics = disableDiagnostics
        }

        if let enableCacheByFile = args["enableCacheByFile"] as? Bool {
            self.optionsInternal.enableCacheByFile = enableCacheByFile
        }

        if let disableHashing = args["disableHashing"] as? Bool {
            self.optionsInternal.disableHashing = disableHashing
        }

        if let disableCompression = args["disableCompression"] as? Bool {
            self.optionsInternal.disableCompression = disableCompression
        }

        if let initializeValues = args["initializeValues"] as? [String: Any] {
            self.optionsInternal.initializeValues = initializeValues
        }
    }

    @objc override public init() {
        self.optionsInternal = StatsigOptions()
    }

    // - DEPRECATED -
    // These are left to prevent breaking changes.
    // Do not add more individual options. Add them to the args dictionary above

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(initTimeout: Double) {
        self.optionsInternal = StatsigOptions(initTimeout: initTimeout)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(disableCurrentVCLogging: Bool) {
        self.optionsInternal = StatsigOptions(disableCurrentVCLogging: disableCurrentVCLogging)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(environment: StatsigEnvironment) {
        self.optionsInternal = StatsigOptions(environment: environment)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(enableAutoValueUpdate: Bool) {
        self.optionsInternal = StatsigOptions(enableAutoValueUpdate: enableAutoValueUpdate)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(overrideStableID: String) {
        self.optionsInternal = StatsigOptions(overrideStableID: overrideStableID)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(environment: StatsigEnvironment, overrideStableID: String) {
        self.optionsInternal = StatsigOptions(environment: environment,
                                              overrideStableID: overrideStableID)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(enableCacheByFile: Bool) {
        self.optionsInternal = StatsigOptions(enableCacheByFile: enableCacheByFile)
    }

    @available(*, deprecated, message: "Use dictionary init instead")
    @objc public init(
        initTimeout: Double,
        disableCurrentVCLogging: Bool,
        environment: StatsigEnvironment,
        enableAutoValueUpdate: Bool,
        overrideStableID: String,
        enableCacheByFile: Bool
    )
    {
        self.optionsInternal = StatsigOptions(
            initTimeout: initTimeout,
            disableCurrentVCLogging: disableCurrentVCLogging,
            environment: environment,
            enableAutoValueUpdate: enableAutoValueUpdate,
            overrideStableID: overrideStableID,
            enableCacheByFile: enableCacheByFile
        )
    }
}
