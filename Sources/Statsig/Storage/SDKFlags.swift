internal struct SDKFlags: Decodable {
    var enableLogEventCompression: Bool = false

    init() {}

    init(from payload: Any?) {
        if let value = (payload as? [String: Any])?["enable_log_event_compression"] as? Bool {
            self.enableLogEventCompression = value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enableLogEventCompression = "enable_log_event_compression"
    }
}
