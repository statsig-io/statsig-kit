public struct BootstrapMetadata {
    var generatorSDKInfo: [String: String]?
    var lcut: Int?
    var user: [String: Any]?

    func toDictionary() -> [String: Any] {
        var dict = [String: Any]()

        if let generatorSDKInfo = generatorSDKInfo {
            dict["generatorSDKInfo"] = generatorSDKInfo
        }

        if let lcut = lcut {
            dict["lcut"] = lcut
        }

        if let user = user {
            dict["user"] = user
        }

        return dict
    }
}
