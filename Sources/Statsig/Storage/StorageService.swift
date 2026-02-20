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

    static func forSDKKeyIfEnabled(
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
            if StorageService.useMultiFileStorage {
                let created = StorageService(sdkKey: sdkKey, storageAdapter: storageAdapter)
                servicesBySDKKey[sdkKey] = created
                return created
            }

            let indexResult = UserPayloadIndexStore.readIndex(
                sdkKey: sdkKey,
                storageAdapter: storageAdapter
            )
            if indexResult.indexFileExists {
                // TODO: Review the scenario where the index file exists but decoding fails. It currently considers the migration done.
                StorageServiceMigrationStatus.markMigrationDone()
                let created = StorageService(
                    sdkKey: sdkKey, storageAdapter: storageAdapter, index: indexResult.index)
                servicesBySDKKey[sdkKey] = created
                return created
            }

            return nil
        }
    }

    static func forSDKKey(_ sdkKey: String, storageProvider: StorageProvider? = nil)
        -> StorageService
    {
        servicesLock.withLock {
            if let existing = servicesBySDKKey[sdkKey] {
                return existing
            }
            let storageAdapter: StorageAdapter =
                storageProvider.map { StorageProviderToAdapter(storageProvider: $0) }
                ?? FileStorageAdapter()
            let created = StorageService(sdkKey: sdkKey, storageAdapter: storageAdapter)
            servicesBySDKKey[sdkKey] = created
            return created
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

    // TODO: Only change value once per session, using an in-memory value (maybe)
    // NOTE: If the SDK or gate switches off, this won't disable the multi-file storage for existing users
    // NOTE: For the scenario where multiple clients have diverging values, we'll switch the storage type if any of them enables it
    static func processSDKConfigs(payload: [String: Any]) {
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

    internal static func clearCachedInstances() {
        servicesLock.withLock {
            servicesBySDKKey.removeAll()
        }
    }

}
