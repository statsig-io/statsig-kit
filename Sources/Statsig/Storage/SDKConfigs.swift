import Foundation

internal struct SDKConfigs: Decodable {
    var multiFileStoreGate: String? = nil

    init() {}

    init(from payload: Any?) {
        if let value = (payload as? [String: Any])?["store_g"] as? String {
            self.multiFileStoreGate = value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case multiFileStoreGate = "store_g"
    }
}
