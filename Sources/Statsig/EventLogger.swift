import Foundation

class EventLogger {
    private static let eventQueueLabel = "com.Statsig.eventQueue"
    private static let nonExposedChecksEvent = "non_exposed_checks"

    let networkService: NetworkService
    let failedRequestStore: FailedLogRequestStore

    let logQueue = DispatchQueue(label: eventQueueLabel, qos: .userInitiated)

    // Test utils
    var maxEventQueueSize: Int = 50

    // Only on logQueue
    var events: [Event]
    private var nonExposedChecks: [String: Int]
    private var exposuresDedupeDict = [DedupeKey: TimeInterval]()

    // Only on main thread
    var flushTimer: Timer?

    @LockedValue
    var user: StatsigUser
    @LockedValue
    private var loggedErrorMessage: Set<String>

    init(
        sdkKey: String,
        user: StatsigUser,
        networkService: NetworkService,
        userDefaults: DefaultsLike = StatsigUserDefaults.defaults
    ) {
        self.events = [Event]()
        self.user = user
        self.networkService = networkService
        self.loggedErrorMessage = Set<String>()
        self.failedRequestStore = FailedLogRequestStore.forSDKKey(
            sdkKey,
            storageProvider: networkService.statsigOptions.storageProvider,
            userDefaults: userDefaults
        )
        self.nonExposedChecks = [String: Int]()
    }

    internal func retryFailedRequests(forUser user: StatsigUser) {
        logQueue.async { [weak self] in
            guard
                let self = self,
                self.networkService.statsigOptions.eventLoggingEnabled
            else { return }

            let requestsToRetry = self.failedRequestStore.takeRequestsForRetry()
            guard !requestsToRetry.isEmpty else { return }

            let failedRequestStore = self.failedRequestStore
            let logQueue = self.logQueue
            self.networkService.sendRequestsWithData(requestsToRetry, forUser: user) {
                failedRequests in
                logQueue.async {
                    failedRequestStore.addRequests(failedRequests)
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

            if self.events.count >= self.maxEventQueueSize {
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
            self?.flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true)
            { [weak self] _ in
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

    private func flushInternal(
        isShuttingDown: Bool = false, persistPendingEvents: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let pendingDroppedRequestSummary = failedRequestStore.takePendingDroppedRequestSummary()
        if events.isEmpty && pendingDroppedRequestSummary == nil {
            completion?()
            return
        }

        let user = self.user
        let oldEvents = events
        events = []
        let requestEvents: [Event]
        if let pendingDroppedRequestSummary {
            requestEvents = oldEvents + [pendingDroppedRequestSummary.makeEvent()]
        } else {
            requestEvents = oldEvents
        }

        let capturedSelf = isShuttingDown ? self : nil

        let requestData: Data
        let requestEventCount = oldEvents.count + (pendingDroppedRequestSummary?.eventCount ?? 0)
        do {
            requestData = try networkService.prepareEventRequestBody(
                forUser: user, events: requestEvents
            ).get()
        } catch {
            restoreDroppedRequestSummary(
                pendingDroppedRequestSummary,
                droppedEventCount: oldEvents.count
            )
            logErrorMessageOnce(error.localizedDescription)
            completion?()
            return
        }

        if !networkService.statsigOptions.eventLoggingEnabled {
            failedRequestStore.addRequest(
                requestData,
                lastFailedAtMs: Time.now(),
                requestEventCount: requestEventCount
            )
            completion?()
            return
        }

        if persistPendingEvents {
            failedRequestStore.addRequest(
                requestData,
                lastFailedAtMs: Time.now(),
                requestEventCount: requestEventCount
            )
        }

        networkService.sendEvents(forUser: user, uncompressedBody: requestData) {
            [weak self, capturedSelf] errorMessage in
            guard let self = self ?? capturedSelf else {
                completion?()
                return
            }

            self.logQueue.async {
                let queuedRequest =
                    persistPendingEvents
                    ? self.failedRequestStore.takeRequest(requestData)
                    : nil

                if let errorMessage = errorMessage {
                    self.failedRequestStore.addOrUpdateRequest(
                        queuedRequest?.body ?? requestData,
                        lastFailedAtMs: Time.now(),
                        requestEventCount: queuedRequest?.requestEventCount ?? requestEventCount
                    )
                    self.logErrorMessageOnce(errorMessage)
                }

                DispatchQueue.global().async {
                    completion?()
                }
            }
        }
    }

    private func restoreDroppedRequestSummary(
        _ pendingDroppedRequestSummary: DroppedLogRequestSummary?,
        droppedEventCount: Int
    ) {
        guard pendingDroppedRequestSummary != nil || droppedEventCount > 0 else {
            return
        }

        var restoredSummary =
            pendingDroppedRequestSummary
            ?? DroppedLogRequestSummary(eventCount: 0, lastFailedAtMs: 0)
        restoredSummary.eventCount += droppedEventCount
        restoredSummary.lastFailedAtMs = max(restoredSummary.lastFailedAtMs, Time.now())
        failedRequestStore.restorePendingDroppedRequestSummary(restoredSummary)
    }

    func logErrorMessageOnce(_ errorMessage: String, user: StatsigUser? = nil) {
        if shouldLogErrorMessage(errorMessage) {
            self.log(
                Event.statsigInternalEvent(
                    user: user ?? self.user,
                    name: "log_event_failed",
                    value: nil,
                    metadata: ["error": errorMessage])
            )
        }
    }

    private func shouldLogErrorMessage(_ errorMessage: String) -> Bool {
        if errorMessage.isEmpty { return false }

        return $loggedErrorMessage.withLock { loggedErrorMessage in
            if loggedErrorMessage.contains(errorMessage) {
                return false
            }

            loggedErrorMessage.insert(errorMessage)
            return true
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
        if self.nonExposedChecks.isEmpty {
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

    static func deleteLocalStorage(sdkKey: String) {
        FailedLogRequestStore.deleteLocalStorage(sdkKey: sdkKey)
        StatsigUserDefaults.defaults.removeObject(
            forKey: UserDefaultsKeys.getFailedEventsStorageKey(sdkKey))
    }
}
