import Foundation

final class StorageService {

    // TODO: Delete this static variable once we ship multi-file storage
    internal static var useMultiFileStorage: Bool {
        return StorageServiceMigrationStatus.migrationStatus != .initial
    }

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

    // TODO: Multi-client
    // TODO: Only change value once per session, using an in-memory value (maybe)
    // NOTE: If the SDK or gate switches off, this won't disable the multi-file storage for existing users
    func processSDKConfigs(payload: [String: Any]) {
        guard
            !StorageService.useMultiFileStorage,
            let configs = payload[InternalStore.sdkConfigsKey] as? [String: Any]
        else {
            return
        }

        let sdkConfigs = SDKConfigs(from: configs)
        let hashUsed = payload[InternalStore.hashUsedKey] as? String
        guard
            let multiFileStoreGate = sdkConfigs.multiFileStoreGate,
            !multiFileStoreGate.isEmpty,
            let gates = payload[InternalStore.gatesKey] as? [String: Any],
            let gate = gates[multiFileStoreGate.hashSpecName(hashUsed)] as? [String: Any],
            let gateValue: Bool = gate["value"] as? Bool,
            gateValue
        else {
            return
        }

        // This enables the new storage going forward
        StorageServiceMigrationStatus.setNeedsMigration()
    }

    // MARK: Test utils

    internal static func clearCachedServices() {
        servicesLock.withLock {
            servicesBySDKKey.removeAll()
        }
    }

}
