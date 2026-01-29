internal struct SDKFlags: Decodable {
    var enableLogEventCompression: Bool = false
    var storeExperiment: String? = nil

    init() {}

    init(from payload: Any?) {
        if let value = (payload as? [String: Any])?["enable_log_event_compression"] as? Bool {
            self.enableLogEventCompression = value
        }
        if let value = (payload as? [String: Any])?["store_xp"] as? String {
            self.storeExperiment = value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enableLogEventCompression = "enable_log_event_compression"
        case storeExperiment = "store_xp"
    }
}
