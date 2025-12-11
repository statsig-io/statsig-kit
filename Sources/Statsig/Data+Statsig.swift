import Foundation

extension Data {
    var json: [String: Any]? {
        guard let result = try? JSONSerialization.jsonObject(with: self, options: []) else {
            return nil
        }
        return result as? [String: Any]
    }

    var text: String? {
        return String(data: self, encoding: .utf8)
    }
}
