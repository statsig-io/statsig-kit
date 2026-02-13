import Foundation

final class StorageService {

    // TODO: Delete this static variable once we ship multi-file storage
    internal static var useMultiFileStorage = false

    private static let servicesLock = NSLock()
    private static var servicesBySDKKey: [String: StorageService] = [:]

    let sdkKey: String
    let userPayload: UserPayloadStore

    static func forSDKKey(_ sdkKey: String) -> StorageService {
        servicesLock.withLock {
            if let existing = servicesBySDKKey[sdkKey] {
                return existing
            }
            let created = StorageService(sdkKey: sdkKey)
            servicesBySDKKey[sdkKey] = created
            return created
        }
    }

    init(sdkKey: String) {
        self.sdkKey = sdkKey
        self.userPayload = UserPayloadStore.forSDKKey(sdkKey)
    }

    // MARK: Test utils

    internal static func clearCachedServices() {
        servicesLock.withLock {
            servicesBySDKKey.removeAll()
        }
    }

}
