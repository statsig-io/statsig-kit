import Foundation

struct UserCacheKey {
    let v1: String
    let v2: String
    let full: String

    static func from(_ options: StatsigOptions, _ user: StatsigUser, _ sdkKey: String)
        -> UserCacheKey
    {
        let customCacheKey = options.customCacheKey?(sdkKey, user)

        let v1 = customCacheKey ?? getVersion1(user)
        let v2 = customCacheKey ?? getVersion2(user, sdkKey)
        let full = getFullUserCacheKey(user, sdkKey)
        return UserCacheKey(v1: v1, v2: v2, full: full)
    }

    private static func getVersion1(_ user: StatsigUser) -> String {
        var key = user.userID ?? "null"
        if let customIDs = user.customIDs {
            for (idType, idValue) in customIDs {
                key += "\(idType)\(idValue)"
            }
        }
        return key
    }

    // uid:USER_ID|cids:CUSTOM_ID_KEY-CUSTOM_ID_VALUE|k:SDK_KEY
    private static func getVersion2(_ user: StatsigUser, _ sdkKey: String) -> String {
        let cids: [String] =
            user.customIDs?.map { key, value in
                return "\(key)-\(value)"
            } ?? []

        return [
            "uid:\(user.userID ?? "")",
            "cids:\(cids.sorted().joined(separator: ","))",
            "k:\(sdkKey)",
        ].joined(separator: "|")
            .djb2()
    }

    static func getFullUserCacheKey(_ user: StatsigUser, _ sdkKey: String) -> String {
        return "\(user.getFullUserHash()):\(sdkKey)"
    }
}
