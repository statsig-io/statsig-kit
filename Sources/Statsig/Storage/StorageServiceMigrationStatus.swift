import Foundation

enum StorageServiceMigrationStatus: Sendable, Equatable {
    case legacy
    case migrating(started: Bool)
    case multiFile

    private static let lock = NSLock()
    private static var state: StorageServiceMigrationStatus?
    private static var hasStateBeenSet = false

    static var migrationStatus: StorageServiceMigrationStatus {
        get {
            lock.withLock {
                return getMigrationStatusLocked()
            }
        }
        set(newValue) {
            lock.withLock {
                state = newValue
                persistState(newValue)
            }
        }
    }

    // MARK: Lock helpers

    private static func withMigrationStatusLock<T>(
        callback: (inout StorageServiceMigrationStatus) -> T
    ) -> T {
        lock.withLock {
            var state = getMigrationStatusLocked()
            let result = callback(&state)
            self.state = state
            persistState(state)
            return result
        }
    }

    private static func getMigrationStatusLocked() -> StorageServiceMigrationStatus {
        if let state = state {
            return state
        }

        let loaded = loadPersistedState()
        state = loaded
        return loaded
    }

    // MARK: Helpers

    static func setNeedsMigration() {
        withMigrationStatusLock { state in
            if !hasStateBeenSet && state == .legacy {
                hasStateBeenSet = true
                state = .migrating(started: false)
            }
        }
    }

    static func useLegacy() {
        withMigrationStatusLock { state in
            if !hasStateBeenSet && state != .legacy {
                hasStateBeenSet = true
                state = .legacy
            }
        }
    }

    static func beginMigrationIfNeeded() -> Bool {
        return withMigrationStatusLock { (state) -> Bool in
            guard state == .migrating(started: false) else {
                return false
            }

            state = .migrating(started: true)
            return true
        }
    }

    static func isMigrating() -> Bool {
        if case .migrating = self.migrationStatus {
            return true
        }
        return false
    }

    static func markMigrationDone() {
        self.migrationStatus = .multiFile
    }

    static func applyStorageTypeOption(_ storageType: StatsigOptions.EXPERIMENTAL_StorageType) {
        withMigrationStatusLock { state in
            guard storageType != .auto, !hasStateBeenSet else { return }
            hasStateBeenSet = true
            if storageType == .legacy {
                state = .legacy
                return
            }

            if storageType == .multiFile, state == .legacy {
                state = .migrating(started: false)
            }
        }
    }

    static func resetState(
        migrationStatus: StorageServiceMigrationStatus? = nil,
        hasStateBeenSet: Bool = false,
        persist: Bool = true
    ) {
        lock.withLock {
            self.state = migrationStatus
            self.hasStateBeenSet = hasStateBeenSet
            if persist {
                persistState(migrationStatus ?? .legacy)
            }
        }
    }

    // MARK: Persistence

    private static func loadPersistedState() -> StorageServiceMigrationStatus {
        let rawValue = StatsigUserDefaults.defaults.string(
            forKey: UserDefaultsKeys.storageMigrationStatusKey)

        switch rawValue {
        case "migrating":
            return .migrating(started: false)
        case "multi-file":
            return .multiFile
        default:
            return .legacy
        }
    }

    private static func persistState(_ state: StorageServiceMigrationStatus) {
        switch state {
        case .legacy:
            StatsigUserDefaults.defaults.removeObject(
                forKey: UserDefaultsKeys.storageMigrationStatusKey)
        case .migrating:
            StatsigUserDefaults.defaults.setValue(
                "migrating", forKey: UserDefaultsKeys.storageMigrationStatusKey)
        case .multiFile:
            StatsigUserDefaults.defaults.setValue(
                "multi-file", forKey: UserDefaultsKeys.storageMigrationStatusKey)
        }
    }
}
