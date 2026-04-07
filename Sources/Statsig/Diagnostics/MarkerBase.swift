import Dispatch
import Foundation

fileprivate let TIME_OFFSET = DispatchTime.now().uptimeNanoseconds
fileprivate let NANO_IN_MS = 1_000_000.0

enum MarkerContext: String {
    case initialize = "initialize"
    case apiCall = "api_call"
}

final class MarkerRecorder {
    @LockedValue
    private var markersByContext: [MarkerContext: [[String: Any]]] = [:]

    func append(context: MarkerContext, marker: [String: Any]) {
        $markersByContext.withLock { unlocked in
            unlocked[context, default: []].append(marker)
        }
    }

    func consumeMarkers(forContext context: MarkerContext) -> [[String: Any]] {
        $markersByContext.withLock { unlocked in
            let markers = unlocked[context] ?? []
            unlocked[context] = []
            return markers
        }
    }

    func markerCount(forContext context: MarkerContext) -> Int {
        markersByContext[context]?.count ?? 0
    }
}

class MarkerBase {
    let context: MarkerContext
    let markerKey: String?

    private let recorder: MarkerRecorder
    private let offset: UInt64

    init(_ recorder: MarkerRecorder, context: MarkerContext, markerKey: String? = nil) {
        self.context = context
        self.markerKey = markerKey
        self.recorder = recorder
        self.offset = TIME_OFFSET
    }

    func start(_ args: [String: Any]) {
        add("start", markerKey, args)
    }

    func end(_ args: [String: Any]) {
        add("end", markerKey, args)
    }

    func getMarkerCount() -> Int {
        return recorder.markerCount(forContext: context)
    }

    private func add(_ action: String, _ markerKey: String?, _ args: [String: Any]) {
        var marker = args
        marker["key"] = marker["key"] ?? markerKey
        marker["action"] = action
        marker["timestamp"] = now()
        recorder.append(context: context, marker: marker)
    }

    private func now() -> Double {
        return Double(DispatchTime.now().uptimeNanoseconds - offset) / NANO_IN_MS
    }
}
