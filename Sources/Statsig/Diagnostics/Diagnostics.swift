protocol MarkersContainer {
    var overall: OverallMarker { get }
    var initialize: InitializeMarkers { get }
}

typealias MarkerAtomicDict = AtomicDictionary<[[String: Any]]>

class Diagnostics {
    private static var instance: DiagnosticsImpl?
    internal static var sampling = Int.random(in: 1...10000)
    private static var disableCoreAPI = false

    static var mark: MarkersContainer? {
        return instance
    }

    static func boot(_ options: StatsigOptions?) {
        if options?.disableDiagnostics == true {
            disableCoreAPI = true
        }

        instance = DiagnosticsImpl()
    }

    static func shutdown() {
        instance = nil
    }

    static func log(_ logger: EventLogger, user: StatsigUser, context: MarkerContext) {
        guard
            let instance = instance,
            let markers = instance.getMarkers(forContext: context),
            !markers.isEmpty
        else {
            return
        }

        if disableCoreAPI && context == MarkerContext.apiCall {
            return
        }

        instance.clearMarkers(forContext: context)

        let event = DiagnosticsEvent(user, context.rawValue, markers)
        logger.log(event)
    }
}

fileprivate class DiagnosticsImpl: MarkersContainer {
    var overall: OverallMarker
    var initialize: InitializeMarkers

    private var markers = MarkerAtomicDict(label: "com.Statsig.Diagnostics")

    fileprivate init() {
        self.overall = OverallMarker(markers)
        self.initialize = InitializeMarkers(markers)
    }

    func getMarkers(forContext context: MarkerContext) -> [[String: Any]]? {
        return markers[context.rawValue]
    }

    fileprivate func clearMarkers(forContext context: MarkerContext) {
        markers[context.rawValue] = []
    }
}
