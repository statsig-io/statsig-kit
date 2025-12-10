import Foundation

internal func getFailedEventStorageKey(_ sdkKey: String) -> String {
    return "\(EventLogger.failedLogsKey):\(sdkKey.djb2())"
}

class EventLogger {
    internal static let failedLogsKey = "com.Statsig.EventLogger.loggingRequestUserDefaultsKey"

    private static let eventQueueLabel = "com.Statsig.eventQueue"
    private static let nonExposedChecksEvent = "non_exposed_checks"

    let networkService: NetworkService
    let userDefaults: DefaultsLike

    let logQueue = DispatchQueue(label: eventQueueLabel, qos: .userInitiated)
    let failedRequestLock = NSLock()
    let storageKey: String

    var maxEventQueueSize: Int = 50
    var events: [Event]
    var failedRequestQueue: [Data]
    var loggedErrorMessage: Set<String>
    var flushTimer: Timer?
    var user: StatsigUser
    var nonExposedChecks: [String: Int]

    private var exposuresDedupeDict = [DedupeKey: TimeInterval]()

#if os(tvOS)
    let MAX_SAVED_LOG_REQUEST_SIZE = 100_000 //100 KB
#else
    let MAX_SAVED_LOG_REQUEST_SIZE = 1_000_000 //1 MB
#endif

    init(
        sdkKey: String,
        user: StatsigUser,
        networkService: NetworkService,
        userDefaults: DefaultsLike = StatsigUserDefaults.defaults
    ) {
        self.events = [Event]()
        self.failedRequestQueue = [Data]()
        self.user = user
        self.networkService = networkService
        self.loggedErrorMessage = Set<String>()
        self.userDefaults = userDefaults
        self.storageKey = getFailedEventStorageKey(sdkKey)
        self.nonExposedChecks = [String: Int]()
    }

    internal func retryFailedRequests(forUser user: StatsigUser) {
        logQueue.async { [weak self] in
            guard
                let self = self,
                self.networkService.statsigOptions.eventLoggingEnabled
            else { return }
            if let failedRequestsCache = userDefaults.array(forKey: storageKey) as? [Data], !failedRequestsCache.isEmpty {
                userDefaults.removeObject(forKey: storageKey)
                
                networkService.sendRequestsWithData(failedRequestsCache, forUser: user) { [weak self] failedRequestsData in
                    guard let failedRequestsData = failedRequestsData else { return }
                    self?.addFailedLogRequest(failedRequestsData)
                    self?.saveFailedLogRequestsToDisk()
                }
            }
        }
    }

    func log(_ event: Event, exposureDedupeKey: DedupeKey? = nil) {
        logQueue.async { [weak self] in
            guard let self = self else { return }

            if let key = exposureDedupeKey {
                let now = Date().timeIntervalSince1970

                if let lastTime = exposuresDedupeDict[key], lastTime >= now - 600 {
                    // if the last time the exposure was logged was less than 10 mins ago, do not log exposure
                    return
                }

                exposuresDedupeDict[key] = now
            }

            self.events.append(event)

            if (self.events.count >= self.maxEventQueueSize) {
                self.flush()
            }
        }
    }

    internal func clearExposuresDedupeDict() {
        logQueue.async(flags: .barrier) { [weak self] in
            self?.exposuresDedupeDict.removeAll()
        }
    }

    func start(flushInterval: TimeInterval = 60) {
        DispatchQueue.main.async { [weak self] in
            self?.flushTimer?.invalidate()
            self?.flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
                self?.flush()
            }
        }
    }

    func stop(persistPendingEvents: Bool = false, completion: (() -> Void)? = nil) {
        ensureMainThread { [weak self] in
            self?.flushTimer?.invalidate()
        }
        logQueue.sync {
            self.addNonExposedChecksEvent()
            self.flushInternal(isShuttingDown: true, persistPendingEvents: persistPendingEvents) {
                guard let completion = completion else { return }
                DispatchQueue.global().async { completion() }
            }
        }
    }

    func flush(persistPendingEvents: Bool = false, completion: (() -> Void)? = nil) {
        logQueue.async { [weak self] in
            self?.addNonExposedChecksEvent()
            self?.flushInternal(persistPendingEvents: persistPendingEvents) {
                guard let completion = completion else { return }
                DispatchQueue.global().async { completion() }
            }
        }
    }

    func removePendingEventsData(_ requestData: Data) {
        failedRequestLock.withLock {
            for (i, req) in failedRequestQueue.enumerated() {
                if (req == requestData) {
                    failedRequestQueue.remove(at: i)
                    return
                }
            }
        }
    }

    private func flushInternal(isShuttingDown: Bool = false, persistPendingEvents: Bool = false, completion: (() -> Void)? = nil) {
        if events.isEmpty {
            completion?()
            return
        }

        let oldEvents = events
        events = []

        if !networkService.statsigOptions.eventLoggingEnabled {
            addFailedLogEvents(oldEvents, forUser: user)
            saveFailedLogRequestsToDisk()
            completion?()
            return
        }

        let capturedSelf = isShuttingDown ? self : nil

        let requestData: Data
        do {
            requestData = try networkService.prepareEventRequestBody(forUser: user, events: oldEvents).get()
        } catch {
            logErrorMessageOnce(error.localizedDescription)
            completion?()
            return
        }

        if (persistPendingEvents) {
            self.addSingleFailedLogRequest(requestData)
            self.saveFailedLogRequestsToDisk()
        }

        networkService.sendEvents(forUser: user, uncompressedBody: requestData) {
            [weak self, capturedSelf] errorMessage in
            guard let self = self ?? capturedSelf else {
                completion?()
                return
            }

            if let errorMessage = errorMessage {

                self.addSingleFailedLogRequest(requestData)
                self.saveFailedLogRequestsToDisk()

                self.logErrorMessageOnce(errorMessage)
            } else if (persistPendingEvents) {
                self.removePendingEventsData(requestData)
                self.saveFailedLogRequestsToDisk()
            }

            completion?()
        }
    }

    func logErrorMessageOnce(_ errorMessage: String, user: StatsigUser? = nil) {
        if !errorMessage.isEmpty && !self.loggedErrorMessage.contains(errorMessage) {
            self.loggedErrorMessage.insert(errorMessage)
            self.log(Event.statsigInternalEvent(
                user: user ?? self.user,
                name: "log_event_failed",
                value: nil,
                metadata: ["error": errorMessage])
            )
        }
    }

    func incrementNonExposedCheck(_ configName: String) {
        logQueue.async { [weak self] in
            guard let self = self else {
                return
            }

            let count = self.nonExposedChecks[configName] ?? 0
            self.nonExposedChecks[configName] = count + 1
        }
    }

    func addNonExposedChecksEvent() {
        if (self.nonExposedChecks.isEmpty) {
            return
        }

        guard JSONSerialization.isValidJSONObject(nonExposedChecks),
              let data = try? JSONSerialization.data(withJSONObject: nonExposedChecks),
              let json = String(data: data, encoding: .ascii)
        else {
            self.nonExposedChecks = [String: Int]()
            return
        }

        let event = Event.statsigInternalEvent(
            user: nil,
            name: EventLogger.nonExposedChecksEvent,
            value: nil,
            metadata: [
                "checks": json
            ]
        )
        self.events.append(event)
        self.nonExposedChecks = [String: Int]()
    }

    private func addFailedLogEvents(_ events: [Event], forUser user: StatsigUser) {
        let bodyResult = networkService.prepareEventRequestBody(forUser: user, events: events)
        do {
            addSingleFailedLogRequest(try bodyResult.get())
        } catch {
            logErrorMessageOnce(error.localizedDescription, user: user)
        }
    }

    private func addSingleFailedLogRequest(_ requestData: Data?) {
        guard let data = requestData else { return }

        addFailedLogRequest([data])
    }

    internal func addFailedLogRequest(_ requestData: [Data]) {
        failedRequestLock.lock()
        defer { failedRequestLock.unlock() }

        failedRequestQueue += requestData

        // Find the cut-off point where total size exceeds the maximum
        var cutoffIndex: Int? = nil
        var cumulativeSize: Int = 0
        for (index, data) in failedRequestQueue.enumerated().reversed() {
            cumulativeSize += data.count
            if cumulativeSize > MAX_SAVED_LOG_REQUEST_SIZE {
                cutoffIndex = index
                break
            }
        }

        // If we exceeded the size limit, remove older entries
        if let cutoffIndex = cutoffIndex {
            failedRequestQueue.removeSubrange(0...cutoffIndex)
        }
    }

    internal func saveFailedLogRequestsToDisk() {
        // `self` is strongly captured explictly to ensure we save to disk
        ensureMainThread { [self] in
            failedRequestLock.lock()
            defer { failedRequestLock.unlock() }

            userDefaults.setValue(
                failedRequestQueue,
                forKey: storageKey
            )
        }
    }

    static func deleteLocalStorage(sdkKey: String) {
        StatsigUserDefaults.defaults.removeObject(forKey: getFailedEventStorageKey(sdkKey))
    }
}
