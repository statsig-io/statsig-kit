import Foundation

internal let ApiHost = "featureassets.org"
internal let LogEventHost = "prodregistryv2.org"

/**
 Configuration options for the StatsigSDK.
 */
public class StatsigOptions {
    public enum EvaluationCallbackData {
        case gate(FeatureGate)
        case config(DynamicConfig)
        case experiment(DynamicConfig)
        case layer(Layer)
        case parameterStore(ParameterStore)
    }

    /**
     Used to decide how long the Statsig client waits for the initial network request to respond before calling the completion block. The Statsig client will return either cached values (if any) or default values if checkGate/getConfig/getExperiment is called before the initial network request completes
     */
    public var initTimeout = 3.0

    /**
     By default, any custom event your application logs with Statsig.logEvent() includes the current root View Controller. This is so we can generate user journey funnels for your users. You can set this parameter to true to disable this behavior.
     */
    public var disableCurrentVCLogging = false

    /**
     By default, feature values for a user are fetched once during Statsig.start and don't change throughout the session. Setting this value to true will make Statsig periodically fetch updated values for the current user.
     */
    public var enableAutoValueUpdate = false

    /**
     Only applies if StatsigOptions.enableAutoValueUpdate is true. Controls how fequently calls to refresh the current users values are made. Time is in seconds and defaults to 60 seconds.
     */
    public var autoValueUpdateIntervalSec = 60.0

    /**
     Overrides the auto generated StableID that is set for the device.
     */
    public var overrideStableID: String?

    /**
     Use file caching instead of UserDefaults. Useful if you are running into size limits with UserDefaults (ie tvOS)
     */
    public var enableCacheByFile = false

    /**
     Provide a Dictionary representing the "initiailize response" required  to synchronously initialize the SDK.
     This value can be obtained from a Statsig server SDK.
     */
    public var initializeValues: [String: Any]? = nil

    /**
     Prevent the SDK from sending useful debug information to Statsig
     */
    public var disableDiagnostics = false

    /**
     Controls whether the SDK sends events over the network.
     */
    public var eventLoggingEnabled = true

    /**
     When disabled, the SDK will not hash gate/config/experiment names, instead they will be readable as plain text.
     Note: This requires special authorization from Statsig. Reach out to us if you are interested in this feature.
     */
    public var disableHashing = false

    /**
     When disabled, the SDK will not compress events sent to Statsig
     */
    public var disableCompression = false

    /**
     The SDK automatically shuts down when an app is put into the background.
     If you need to use the SDK while your app is backgrounded, set this to false.
     */
    public var shutdownOnBackground = true

    /**
     The URL used to initialize the SDK. You should not need to override this (unless you have another endpoint that implements the Statsig initialization endpoint)
     */
    public var initializationURL: URL? = nil

    /**
     The URL used for log_event network requests. You should not need to override this (unless you have another API that implements the Statsig /v1/rgstr endpoint)
     */
    public var eventLoggingURL: URL? = nil

    /**
     The API to use for initialization network requests. Any path will be replaced with /v1/initialize. If you need a custom path, set the full URL to initializationURL.
     You should not need to override this (unless you have another API that implements the Statsig API endpoints)
     */
    public var api: String {
        get {
            return initializationURL?.ignoringPath?.absoluteString ?? "https://\(ApiHost)"
        }
        set {
            if let apiURL = URL(string: newValue)?.ignoringPath {
                self.initializationURL = apiURL.appendingPathComponent(
                    Endpoint.initialize.rawValue, isDirectory: false)
            } else {
                PrintHandler.log(
                    "[Statsig]: Failed to create URL with StatsigOptions.api. Please check if it's a valid URL"
                )
            }
        }
    }

    /**
     The API to use for log_event network requests. Any path will be replaced with /v1/rgstr. If you need a custom path, set the full URL to eventLoggingURL.
     You should not need to override this (unless you have another API that implements the Statsig /v1/rgstr endpoint)
     */
    public var eventLoggingApi: String {
        get {
            return eventLoggingURL?.ignoringPath?.absoluteString ?? "https://\(LogEventHost)"
        }
        set {
            if let apiURL = URL(string: newValue)?.ignoringPath {
                self.eventLoggingURL = apiURL.appendingPathComponent(
                    Endpoint.logEvent.rawValue, isDirectory: false)
            } else {
                PrintHandler.log(
                    "[Statsig]: Failed to create URL with StatsigOptions.eventLoggingApi. Please check if it's a valid URL"
                )
            }
        }
    }

    /**
     A callback to validate the user on initialization/updateUser.
     */
    public var userValidationCallback: ((StatsigUser) -> StatsigUser)?

    /**
     A callback for when an evaluation is made against one of your configurations (gate, dynamic config, experiment or layer).
     */
    public var evaluationCallback: ((EvaluationCallbackData) -> Void)?

    /**
     Overrides the default cache key generation. Given the SDKKey and current StatsigUser, return a key to be used for storing values related to that user.
     Default key is a hash of the sdkKey, user.userID, and  user.customIDs.
     */
    public var customCacheKey: ((String, StatsigUser) -> String)?

    /**
        Provides a customizable storage mechanism for the SDK.
        Users can pass an object that conforms to the `StorageProvider` protocol, allowing them to implement
        their own caching strategy for reading from and writing to the cache (e.g., using an encrypted file on disk).
    */
    public var storageProvider: StorageProvider?

    /**
     The URLSession to be used for network requests. By default, it is set to URLSession.shared.
     This property can be customized to utilize URLSession instances with specific configurations, including certificate pinning, for enhanced security when communicating with servers.
     */
    public var urlSession: URLSession = .shared

    /**
     A handler for log messages from the SDK. If not provided, logs will be printed to the console.
     The handler receives the message string that would otherwise be printed to the console.
     */
    public var printHandler: ((String) -> Void)?

    var environment: [String: String] = [:]

    /**
     Event names are trimmed to 64 characters by default. Set this option to true to disable this behavior.
     */
    var disableEventNameTrimming: Bool

    /**
     Adapter for on-device evaluation.
     */
    public var overrideAdapter: OnDeviceEvalAdapter?

    public init(
        initTimeout: Double? = 3.0,
        disableCurrentVCLogging: Bool? = false,
        environment: StatsigEnvironment? = nil,
        enableAutoValueUpdate: Bool? = false,
        autoValueUpdateIntervalSec: Double? = nil,
        overrideStableID: String? = nil,
        enableCacheByFile: Bool? = false,
        initializeValues: [String: Any]? = nil,
        eventLoggingEnabled: Bool? = true,
        disableDiagnostics: Bool? = false,
        disableHashing: Bool? = false,
        disableCompression: Bool? = false,
        shutdownOnBackground: Bool? = true,
        api: String? = nil,
        eventLoggingApi: String? = nil,
        initializationURL: URL? = nil,
        eventLoggingURL: URL? = nil,
        evaluationCallback: ((EvaluationCallbackData) -> Void)? = nil,
        userValidationCallback: ((StatsigUser) -> StatsigUser)? = nil,
        customCacheKey: ((String, StatsigUser) -> String)? = nil,
        storageProvider: StorageProvider? = nil,
        urlSession: URLSession? = nil,
        disableEventNameTrimming: Bool = false,
        overrideAdapter: OnDeviceEvalAdapter? = nil,
        printHandler: ((String) -> Void)? = nil
    ) {
        self.disableEventNameTrimming = disableEventNameTrimming

        if let initTimeout = initTimeout, initTimeout >= 0 {
            self.initTimeout = initTimeout
        }

        if let disableCurrentVCLogging = disableCurrentVCLogging {
            self.disableCurrentVCLogging = disableCurrentVCLogging
        }

        if let environment = environment {
            self.environment = environment.params
        }

        if let enableAutoValueUpdate = enableAutoValueUpdate {
            self.enableAutoValueUpdate = enableAutoValueUpdate
        }

        if let enableCacheByFile = enableCacheByFile {
            self.enableCacheByFile = enableCacheByFile
        }

        if let eventLoggingEnabled = eventLoggingEnabled {
            self.eventLoggingEnabled = eventLoggingEnabled
        }

        if let initializeValues = initializeValues {
            self.initializeValues = initializeValues
        }

        if let disableDiagnostics = disableDiagnostics {
            self.disableDiagnostics = disableDiagnostics
        }

        if let disableHashing = disableHashing {
            self.disableHashing = disableHashing
        }

        if let disableCompression = disableCompression {
            self.disableCompression = disableCompression
        }

        if let shutdownOnBackground = shutdownOnBackground {
            self.shutdownOnBackground = shutdownOnBackground
        }

        if let autoValueUpdateIntervalSec = autoValueUpdateIntervalSec {
            self.autoValueUpdateIntervalSec = autoValueUpdateIntervalSec
        }

        if let storageProvider = storageProvider {
            self.storageProvider = storageProvider
        }

        if let initializationURL = initializationURL {
            self.initializationURL = initializationURL
            if api != nil {
                PrintHandler.log(
                    "[Statsig]: StatsigOptions.api is being ignored because StatsigOptions.initializationURL is also being set."
                )
            }
        } else if let api = api {
            self.api = api
        }

        if let eventLoggingURL = eventLoggingURL {
            self.eventLoggingURL = eventLoggingURL
            if eventLoggingApi != nil {
                PrintHandler.log(
                    "[Statsig]: StatsigOptions.eventLoggingApi is being ignored because StatsigOptions.eventLoggingURL is also being set."
                )
            }
        } else if let eventLoggingApi = eventLoggingApi {
            self.eventLoggingApi = eventLoggingApi
        }

        if let customCacheKey = customCacheKey {
            self.customCacheKey = customCacheKey
        }

        if let urlSession = urlSession {
            self.urlSession = urlSession
        }

        self.overrideStableID = overrideStableID

        self.evaluationCallback = evaluationCallback

        self.userValidationCallback = userValidationCallback

        self.overrideAdapter = overrideAdapter

        self.printHandler = printHandler
    }
}

// MARK: Get dictionary for logging
extension StatsigOptions {
    // Global variables are lazy by default
    static var defaultOptions = StatsigOptions()

    internal func getDictionaryForLogging() -> [String: Any] {
        let defaultOptions = StatsigOptions.defaultOptions

        var dict: [String: Any] = [
            "environment": environment
        ]

        if storageProvider != nil {
            dict["storageProvider"] = "set"
        }
        if overrideAdapter != nil {
            dict["overrideAdapter"] = "set"
        }
        if evaluationCallback != nil {
            dict["evaluationCallback"] = "set"
        }
        if printHandler != nil {
            dict["printHandler"] = "set"
        }
        if customCacheKey != nil {
            dict["customCacheKey"] = "set"
        }
        if userValidationCallback != nil {
            dict["userValidationCallback"] = "set"
        }
        if urlSession != URLSession.shared {
            dict["urlSession"] = "set"
        }
        if let id = overrideStableID, id != defaultOptions.overrideStableID {
            dict["overrideStableID"] = id.count < 50 ? id : "set"
        }
        if let initURL = initializationURL,
            initURL.absoluteString != defaultOptions.initializationURL?.absoluteString
        {
            dict["initializationURL"] = initURL.absoluteString
        }
        if let logURL = eventLoggingURL,
            logURL.absoluteString != defaultOptions.eventLoggingURL?.absoluteString
        {
            dict["eventLoggingURL"] = logURL.absoluteString
        }
        if initTimeout != defaultOptions.initTimeout {
            dict["initTimeout"] = initTimeout
        }
        if autoValueUpdateIntervalSec != defaultOptions.autoValueUpdateIntervalSec {
            dict["autoValueUpdateIntervalSec"] = autoValueUpdateIntervalSec
        }
        if eventLoggingEnabled != defaultOptions.eventLoggingEnabled {
            dict["eventLoggingEnabled"] = eventLoggingEnabled
        }
        if disableCurrentVCLogging != defaultOptions.disableCurrentVCLogging {
            dict["disableCurrentVCLogging"] = disableCurrentVCLogging
        }
        if eventLoggingEnabled != defaultOptions.eventLoggingEnabled {
            dict["eventLoggingEnabled"] = eventLoggingEnabled
        }
        if enableAutoValueUpdate != defaultOptions.enableAutoValueUpdate {
            dict["enableAutoValueUpdate"] = enableAutoValueUpdate
        }
        if enableCacheByFile != defaultOptions.enableCacheByFile {
            dict["enableCacheByFile"] = enableCacheByFile
        }
        if disableDiagnostics != defaultOptions.disableDiagnostics {
            dict["disableDiagnostics"] = disableDiagnostics
        }
        if disableHashing != defaultOptions.disableHashing {
            dict["disableHashing"] = disableHashing
        }
        if disableCompression != defaultOptions.disableCompression {
            dict["disableCompression"] = disableCompression
        }
        if shutdownOnBackground != defaultOptions.shutdownOnBackground {
            dict["shutdownOnBackground"] = shutdownOnBackground
        }
        if disableEventNameTrimming != defaultOptions.disableEventNameTrimming {
            dict["disableEventNameTrimming"] = disableEventNameTrimming
        }

        // Initialize Values dictionary
        if initializeValues != nil {
            dict["initializeValues"] = "set"
        }

        return dict
    }
}

// NOTE: This is here to to prevent a bugfix from causing a breaking change to users of the `api` option
extension URL {
    var ignoringPath: URL? {
        var urlComponents = URLComponents()
        urlComponents.scheme = scheme
        urlComponents.host = host
        urlComponents.port = port
        return urlComponents.url
    }
}
