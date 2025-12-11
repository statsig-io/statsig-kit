import Foundation

internal enum Endpoint: String {
    case initialize = "/v1/initialize"
    case logEvent = "/v1/rgstr"

    var dnsKey: String {
        return switch self {
        case .initialize: "i"
        case .logEvent: "e"
        }
    }
}

fileprivate let RetryLimits: [Endpoint: Int] = [
    .initialize: 3,
    .logEvent: 3,
]

fileprivate typealias NetworkCompletionHandler = (Data?, URLResponse?, Error?) -> Void
fileprivate typealias TaskCaptureHandler = ((URLSessionDataTask) -> Void)?

internal enum CompressionType {
    case gzip
    case none
    func contentEncodingHeader() -> String? {
        return switch self {
        case .gzip: "gzip"
        case .none: nil
        }
    }
}

struct CompressedBody {
    let body: Data
    let compression: CompressionType
}

class NetworkService {
    let sdkKey: String
    let statsigOptions: StatsigOptions
    var store: InternalStore
    var inflightRequests = AtomicDictionary<URLSessionTask>(label: "com.Statsig.InFlightRequests")
    var networkFallbackResolver: NetworkFallbackResolver

    /**
     Default URL used to initialize the SDK. Used for tests.
     */
    internal static var defaultInitializationURL = URL(
        string: "https://\(ApiHost)\(Endpoint.initialize.rawValue)")

    /**
     Default URL used for log_event network requests. Used for tests.
     */
    internal static var defaultEventLoggingURL = URL(
        string: "https://\(LogEventHost)\(Endpoint.logEvent.rawValue)")

    /**
     Disables compression globally. Used for tests.
     */
    internal static var disableCompression = false

    private final let networkRetryErrorCodes = [408, 500, 502, 503, 504, 522, 524, 599]

    private let errorBoundary: ErrorBoundary

    init(sdkKey: String, options: StatsigOptions, store: InternalStore) {
        self.sdkKey = sdkKey
        self.statsigOptions = options
        self.store = store
        self.errorBoundary = ErrorBoundary.boundary(clientKey: sdkKey, statsigOptions: options)
        self.networkFallbackResolver = NetworkFallbackResolver(
            sdkKey: sdkKey, store: store, errorBoundary: self.errorBoundary)
    }

    func fetchUpdatedValues(
        for user: StatsigUser,
        lastSyncTimeForUser: UInt64,
        previousDerivedFields: [String: String],
        fullChecksum: String?,
        completion: ResultCompletionBlock?
    ) {
        let bodyResult = makeReqBody([
            "user": user.toDictionary(forLogging: false),
            "statsigMetadata": user.deviceEnvironment,
            "lastSyncTimeForUser": lastSyncTimeForUser,
            "previousDerivedFields": previousDerivedFields,
            "full_checksum": fullChecksum ?? nil,
            "sinceTime": lastSyncTimeForUser,
            "hash": statsigOptions.disableHashing ? "none" : "djb2",
        ])

        let body: Data
        switch bodyResult {
        case .success(let data):
            body = data
        case .failure(let error):
            self.store.finalizeValues {
                completion?(
                    StatsigClientError(
                        .failedToFetchValues,
                        message: (error as? LocalizedError)?.localizedDescription
                            ?? "Failed to serialize request body",
                        cause: error
                    ))
            }
            return
        }

        let cacheKey = UserCacheKey.from(self.statsigOptions, user, self.sdkKey)
        let fullUserHash = user.getFullUserHash()

        makeAndSendRequest(.initialize, body: body) { [weak self] data, response, error in
            if let error {
                completion?(StatsigClientError(.failedToFetchValues, cause: error))
                return
            }

            let statusCode = response?.status ?? 0

            if !(200...299).contains(statusCode) {
                completion?(
                    StatsigClientError(
                        .failedToFetchValues,
                        message:
                            "An error occurred during fetching values for the user. \(statusCode)"))
                return
            }

            guard let self = self else {
                completion?(
                    StatsigClientError(
                        .failedToFetchValues,
                        message: "Failed to call NetworkService as it has been released"))
                return
            }

            guard let dict = data?.json, dict["has_updates"] as? Bool == true else {
                self.store.finalizeValues {
                    completion?(nil)
                }
                return
            }

            self.store.saveValues(dict, cacheKey, fullUserHash) { completion?(nil) }
        }
    }

    func fetchInitialValues(
        for user: StatsigUser,
        sinceTime: UInt64,
        previousDerivedFields: [String: String],
        fullChecksum: String?,
        marker: NetworkMarker? = nil,
        processMarker: InitializeStepMarker? = nil,
        completion: ResultCompletionBlock?
    ) {
        let cacheKey = UserCacheKey.from(self.statsigOptions, user, self.sdkKey)
        if let inflight = inflightRequests[cacheKey.v2] {
            inflight.cancel()
        }

        if inflightRequests.count() > 50 {
            inflightRequests.reset()
        }

        var task: URLSessionDataTask?
        var completed = false
        let lock = NSLock()

        let done: (StatsigClientError?) -> Void = { [weak self] err in
            // Ensures the completion is invoked only once
            lock.lock()
            defer { lock.unlock() }

            if let req = self?.inflightRequests[cacheKey.v2], req === task,
                req.state != .completed && req.state != .canceling
            {
                req.cancel()
            }
            self?.inflightRequests.removeValue(forKey: cacheKey.v2)

            guard !completed else { return }
            completed = true

            self?.store.finalizeValues(completionQueue: .main) {
                task?.cancel()
                completion?(err)
            }

        }

        if statsigOptions.initTimeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + statsigOptions.initTimeout) {
                done(StatsigClientError(.initTimeoutExpired))
            }
        }

        let bodyResult = makeReqBody([
            "user": user.toDictionary(forLogging: false),
            "statsigMetadata": user.deviceEnvironment,
            "sinceTime": sinceTime,
            "hash": statsigOptions.disableHashing ? "none" : "djb2",
            "previousDerivedFields": previousDerivedFields,
            "full_checksum": fullChecksum ?? nil,
        ])

        let body: Data
        switch bodyResult {
        case .success(let data):
            body = data
        case .failure(let error):
            done(StatsigClientError(.failedToFetchValues, cause: error))
            return
        }

        let fullUserHash = user.getFullUserHash()

        makeAndSendRequest(
            .initialize,
            body: body,
            marker: marker
        ) { [weak self] data, response, error in
            if let error = error {
                done(StatsigClientError(.failedToFetchValues, cause: error))
                return
            }

            let statusCode = response?.status ?? 0

            if !(200...299).contains(statusCode) {
                done(
                    StatsigClientError(
                        .failedToFetchValues,
                        message:
                            "An error occurred during fetching values for the user. \(statusCode)"))
                return
            }

            guard let self = self else {
                done(
                    StatsigClientError(
                        .failedToFetchValues,
                        message: "Failed to call NetworkService as it has been released"))
                return
            }

            processMarker?.start()
            var values: [String: Any]? = nil
            if statusCode == 204 {
                values = ["has_updates": false]
            } else if let json = data?.json {
                values = json
            }

            guard let values = values else {
                processMarker?.end(success: false)
                done(
                    StatsigClientError(
                        .failedToFetchValues, message: "No values returned with initialize response"
                    ))
                return
            }

            self.store.saveValues(values, cacheKey, fullUserHash) {
                processMarker?.end(success: true)
                done(nil)
            }

        } taskCapture: { [weak self] capturedTask in
            self?.inflightRequests[cacheKey.v2] = capturedTask
            task = capturedTask
        }
    }

    func prepareEventRequestBody(forUser user: StatsigUser, events: [Event]) -> Result<Data, Error>
    {
        return makeReqBody([
            "events": events.map { $0.toDictionary() },
            "user": user.toDictionary(forLogging: true),
            "statsigMetadata": user.deviceEnvironment,
        ])
    }

    func sendEvents(
        forUser user: StatsigUser, uncompressedBody: Data,
        completion: @escaping ((_ errorMessage: String?) -> Void)
    ) {
        let compressed = tryCompress(body: uncompressedBody, forUser: user)

        makeAndSendRequest(.logEvent, body: compressed.body, compression: compressed.compression) {
            _, response, error in
            if let error = error {
                completion(error.localizedDescription)
                return
            }

            guard response?.isOK == true else {
                completion(
                    "An error occurred during sending events to server. "
                        + "\(String(describing: response?.status))")
                return
            }

            completion(nil)
        }
    }

    func tryCompress(body: Data, forUser user: StatsigUser) -> CompressedBody {
        #if !os(watchOS)
        guard !self.statsigOptions.disableCompression,
            !NetworkService.disableCompression,
            self.statsigOptions.eventLoggingURL == nil
                || self.store.getSDKFlags(user: user).enableLogEventCompression
        else {
            return CompressedBody(body: body, compression: .none)
        }

        switch gzipped(body) {
        case .success(let compressed):
            return CompressedBody(body: compressed, compression: .gzip)
        case .failure(let error):
            self.errorBoundary.logException(tag: "network_compression_gzip", error: error)
        }
        #endif

        return CompressedBody(body: body, compression: .none)
    }

    func sendRequestsWithData(
        _ dataArray: [Data],
        forUser user: StatsigUser,
        completion: @escaping ((_ failedRequestsData: [Data]?) -> Void)
    ) {
        var failedRequests: [Data] = []
        let dispatchGroup = DispatchGroup()
        for data in dataArray {
            dispatchGroup.enter()
            let compressed = tryCompress(body: data, forUser: user)
            makeAndSendRequest(
                .logEvent, body: compressed.body, compression: compressed.compression
            ) { _, response, error in
                if error != nil || response?.isOK != true {
                    failedRequests.append(data)
                }
                dispatchGroup.leave()
            }
        }
        dispatchGroup.notify(queue: .main) {
            completion(failedRequests)
        }
    }

    private func makeReqBody(_ dict: [String: Any?]) -> Result<Data, Error> {
        if JSONSerialization.isValidJSONObject(dict),
            let data = try? JSONSerialization.data(withJSONObject: dict)
        {
            return .success(data)
        }

        return .failure(StatsigError.invalidJSONParam("requestBody"))
    }

    private func urlForEndpoint(_ endpoint: Endpoint) -> URL? {
        return switch endpoint {
        case .initialize:
            self.statsigOptions.initializationURL ?? self.networkFallbackResolver
                .getActiveFallbackURL(endpoint: endpoint) ?? NetworkService.defaultInitializationURL
        case .logEvent:
            self.statsigOptions.eventLoggingURL ?? self.networkFallbackResolver
                .getActiveFallbackURL(endpoint: endpoint) ?? NetworkService.defaultEventLoggingURL
        }
    }

    private func makeAndSendRequest(
        _ endpoint: Endpoint,
        body: Data,
        compression: CompressionType = .none,
        marker: NetworkMarker? = nil,
        completion: @escaping NetworkCompletionHandler,
        taskCapture: TaskCaptureHandler = nil
    ) {
        guard let requestURL = urlForEndpoint(endpoint) else {
            completion(nil, nil, StatsigError.invalidRequestURL("\(endpoint)"))
            return
        }

        var request = URLRequest(url: requestURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sdkKey, forHTTPHeaderField: "STATSIG-API-KEY")
        request.setValue("\(Time.now())", forHTTPHeaderField: "STATSIG-CLIENT-TIME")
        request.setValue(DeviceEnvironment.sdkType, forHTTPHeaderField: "STATSIG-SDK-TYPE")
        request.setValue(DeviceEnvironment.sdkVersion, forHTTPHeaderField: "STATSIG-SDK-VERSION")
        if let contentEncoding = compression.contentEncodingHeader() {
            request.setValue(contentEncoding, forHTTPHeaderField: "Content-Encoding")
        }
        request.httpBody = body
        request.httpMethod = "POST"

        sendRequest(
            request,
            endpoint: endpoint,
            retryLimit: RetryLimits[endpoint] ?? 0,
            marker: marker,
            completion: completion,
            taskCapture: taskCapture)
    }

    private func endpointOverrideURL(endpoint: Endpoint) -> URL? {
        switch endpoint {
        case .initialize: return self.statsigOptions.initializationURL
        case .logEvent: return self.statsigOptions.eventLoggingURL
        }
    }

    private func sendRequest(
        _ request: URLRequest,
        endpoint: Endpoint,
        failedAttempts: Int = 0,
        retryLimit: Int,
        marker: NetworkMarker? = nil,
        completion: @escaping NetworkCompletionHandler,
        taskCapture: TaskCaptureHandler
    ) {
        let currentAttempt = failedAttempts + 1
        marker?.start(attempt: currentAttempt)

        let task = self.statsigOptions.urlSession.dataTask(with: request) {
            [weak self] responseData, response, error in

            marker?.end(currentAttempt, responseData, response, error)

            guard let self = self else {
                completion(responseData, response, error)
                return
            }

            if error == nil && response?.isOK == true {
                self.networkFallbackResolver.tryBumpExpiryTime(endpoint: endpoint)
            }

            guard failedAttempts < retryLimit else {
                completion(responseData, response, error)
                return
            }

            if let code = response?.status,
                self.networkRetryErrorCodes.contains(code)
            {

                self.sendRequest(
                    request,
                    endpoint: endpoint,
                    failedAttempts: currentAttempt,
                    retryLimit: retryLimit,
                    marker: marker,
                    completion: completion,
                    taskCapture: taskCapture
                )
            } else if self.networkFallbackResolver.isDomainFailure(error: error)
                && self.endpointOverrideURL(endpoint: endpoint) == nil
            {
                // Fallback domains
                self.networkFallbackResolver.tryFetchUpdatedFallbackInfo(endpoint: endpoint) {
                    [weak self] fallbackUpdated in
                    if fallbackUpdated,
                        let self = self,
                        let fallbackUrl = self.networkFallbackResolver.getActiveFallbackURL(
                            endpoint: endpoint)
                    {
                        var newRequest = request
                        newRequest.url = fallbackUrl
                        self.sendRequest(
                            newRequest,
                            endpoint: endpoint,
                            failedAttempts: currentAttempt,
                            retryLimit: retryLimit,
                            marker: marker,
                            completion: completion,
                            taskCapture: taskCapture
                        )
                    } else {
                        completion(responseData, response, error)
                    }
                }
            } else {
                completion(responseData, response, error)
            }
        }

        if let taskCapture = taskCapture {
            taskCapture(task)
        }

        task.resume()
    }

    internal static func defaultURLForEndpoint(_ endpoint: Endpoint) -> URL? {
        return switch endpoint {
        case .initialize: NetworkService.defaultInitializationURL
        case .logEvent: NetworkService.defaultEventLoggingURL
        }
    }
}
