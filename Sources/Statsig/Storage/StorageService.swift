import Foundation

final class StorageService {

    private static let servicesLock = NSLock()
    private static var servicesBySDKKey: [String: StorageService] = [:]

    let sdkKey: String
    let userPayload: UserPayloadStore

    static func forSDKKey(
        _ sdkKey: String,
        storageProvider: StorageProvider? = nil
    ) -> StorageService? {
        servicesLock.withLock {
            if let existing = servicesBySDKKey[sdkKey] {
                return existing
            }

            // NOTE: Separate SDK keys can have separate adapters, but that doesn't apply to migrations.
            let storageAdapter: StorageAdapter =
                storageProvider.map { StorageProviderToAdapter(storageProvider: $0) }
                ?? FileStorageAdapter()

            // If multi-file storage is already enabled by another sdk key in this session,
            // create a service with an empty index for this sdk key.
            if StorageServiceMigrationStatus.migrationStatus != .legacy {
                let created = StorageService(sdkKey: sdkKey, storageAdapter: storageAdapter)
                servicesBySDKKey[sdkKey] = created
                return created
            }

            return nil
        }
    }

    init(
        sdkKey: String, storageAdapter: StorageAdapter,
        index: UserPayloadIndex = UserPayloadIndex.empty()
    ) {
        self.sdkKey = sdkKey
        self.userPayload = UserPayloadStore.forSDKKey(
            sdkKey, storageAdapter: storageAdapter, index: index)
    }

    // NOTE: In auto mode, missing sdk config rolls back the migration status to legacy.
    // NOTE: For the scenario where multiple clients have diverging values, the migration status is shared process-wide.
    static func processSDKConfigs(payload: [String: Any]) {
        guard payload["has_updates"] as? Bool == true else { return }

        guard
            let configs = payload[InternalStore.sdkConfigsKey] as? [String: Any],
            let multiFileStoreGate = configs["store_g"] as? String,
            !multiFileStoreGate.isEmpty
        else {
            StorageServiceMigrationStatus.useLegacy()
            return
        }

        let hashUsed = payload[InternalStore.hashUsedKey] as? String
        guard
            let gates = payload[InternalStore.gatesKey] as? [String: Any],
            let gate = gates[multiFileStoreGate] as? [String: Any] ?? gates[
                multiFileStoreGate.hashSpecName(hashUsed)] as? [String: Any],
            let gateValue: Bool = gate["value"] as? Bool,
            gateValue
        else {
            return
        }

        // This enables the new storage going forward
        StorageServiceMigrationStatus.setNeedsMigration()
    }

    static func sendStorageGateExposureIfNeeded(statsigClient: StatsigClient) {
        guard statsigClient.statsigOptions.EXPERIMENTAL_storageType == .auto else {
            return
        }

        guard
            let gateName = statsigClient.getCurrentSDKConfigs().multiFileStoreGate,
            !gateName.isEmpty
        else {
            return
        }

        _ = statsigClient.checkGate(gateName)
    }

    // MARK: Test utils

    internal static func clearCachedInstances() {
        servicesLock.withLock {
            servicesBySDKKey.removeAll()
        }
    }

}
