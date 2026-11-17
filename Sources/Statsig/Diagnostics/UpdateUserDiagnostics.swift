import Foundation

final class UpdateUserDiagnostics {
    let network: NetworkMarker
    let process: InitializeStepMarker

    private let lock = NSLock()
    private let recorder = MarkerRecorder()
    private let overall: OverallMarker
    private var completed = false

    init() {
        overall = OverallMarker(recorder, context: .updateUser)
        network = NetworkMarker(recorder, key: "initialize", context: .updateUser)
        process = InitializeStepMarker(
            recorder,
            key: "initialize",
            step: "process",
            context: .updateUser
        )
    }

    func start() {
        overall.start()
    }

    func complete(
        _ logger: EventLogger,
        user: StatsigUser,
        success: Bool,
        details: EvaluationDetails,
        errorMessage: String?
    ) {
        lock.withLock {
            guard !completed else {
                return
            }
            completed = true

            overall.end(success: success, details: details, errorMessage: errorMessage)
            let markers = recorder.consumeMarkers(forContext: .updateUser)
            guard !markers.isEmpty else {
                return
            }
            logger.log(DiagnosticsEvent(user, MarkerContext.updateUser.rawValue, markers))
        }
    }
}
