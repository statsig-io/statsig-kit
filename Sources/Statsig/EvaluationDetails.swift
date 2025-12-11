import Foundation

public struct EvaluationDetails: Codable {
    public let source: EvaluationSource

    public var reason: EvaluationReason?
    public var lcut: UInt64?
    public var receivedAt: UInt64?
    public var prefix: String?

    init(
        source: EvaluationSource,
        reason: EvaluationReason? = nil,
        lcut: UInt64? = nil,
        receivedAt: UInt64? = nil,
        prefix: String? = nil
    ) {
        self.source = source
        self.reason = reason
        self.lcut = lcut
        self.receivedAt = receivedAt
        self.prefix = prefix
    }

    func getDetailedReason() -> String {
        var result = "\(self.prefix ?? "")\(source.rawValue)"
        if source == .NoValues || source == .Uninitialized {
            return result
        }

        if let reason = reason {
            result += ":\(reason.rawValue)"
        }
        return result
    }

    func addToDictionary(_ dict: inout [String: Any]) {
        dict["reason"] = getDetailedReason()

        if let lcut = lcut {
            dict["lcut"] = String(lcut)
        }

        if let receivedAt = receivedAt {
            dict["receivedAt"] = String(receivedAt)
        }
    }

    static func uninitialized() -> EvaluationDetails {
        EvaluationDetails(source: .Uninitialized)
    }

    var dedupeKey: DedupeKey {
        DedupeKey(
            prefix: prefix,
            source: source,
            reason: (source == .NoValues || source == .Uninitialized) ? nil : reason
        )
    }

    internal struct DedupeKey: Hashable {
        public let prefix: String?
        public let source: EvaluationSource
        public let reason: EvaluationReason?
    }
}

public enum EvaluationSource: String, Codable {
    case Uninitialized
    case Loading
    case NoValues
    case Network
    case NetworkNotModified
    case Cache
    case Bootstrap
    case InvalidBootstrap
}

public enum EvaluationReason: String, Codable {
    case Recognized
    case Unrecognized
    case Sticky
    case LocalOverride
    case StableIDMismatch
}
