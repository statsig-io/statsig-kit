import Foundation

protocol MarkersContainer {
    var overall: OverallMarker { get }
    var initialize: InitializeMarkers { get }
}

class Diagnostics {
    private static let stateLock = NSLock()
    private static var instance: DiagnosticsImpl?
    private static var _sampling = Int.random(in: 1...10000)
    private static var disableCoreAPI = false

    internal static var sampling: Int {
        get {
            stateLock.withLock { _sampling }
        }
        set {
            stateLock.withLock { _sampling = newValue }
        }
    }

    static var mark: MarkersContainer? {
        stateLock.withLock { instance }
    }

    static func boot(_ options: StatsigOptions?) {
        stateLock.withLock {
            if options?.disableDiagnostics == true {
                disableCoreAPI = true
            }

            instance = DiagnosticsImpl()
        }
    }

    static func shutdown() {
        stateLock.withLock {
            instance = nil
        }
    }

    static func log(_ logger: EventLogger, user: StatsigUser, context: MarkerContext) {
        let state = stateLock.withLock { (instance: instance, disableCoreAPI: disableCoreAPI) }

        guard
            let instance = state.instance
        else {
            return
        }

        if state.disableCoreAPI && context == MarkerContext.apiCall {
            return
        }

        let markers = instance.consumeMarkers(forContext: context)
        guard
            !markers.isEmpty
        else {
            return
        }

        let event = DiagnosticsEvent(user, context.rawValue, markers)
        logger.log(event)
    }
}

fileprivate final class DiagnosticsImpl: MarkersContainer {
    let overall: OverallMarker
    let initialize: InitializeMarkers

    private let recorder = MarkerRecorder()

    fileprivate init() {
        self.overall = OverallMarker(recorder)
        self.initialize = InitializeMarkers(recorder)
    }

    fileprivate func consumeMarkers(forContext context: MarkerContext) -> [[String: Any]] {
        recorder.consumeMarkers(forContext: context)
    }
}
