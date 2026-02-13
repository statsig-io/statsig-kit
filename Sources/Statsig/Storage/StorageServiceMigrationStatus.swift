import Foundation

enum StorageServiceMigrationStatus: Int, Codable, Sendable {
    case initial
    case pending
    case started
    case done

    private static let lock = NSLock()
    private static var state = StorageServiceMigrationStatus.initial

    static var migrationStatus: StorageServiceMigrationStatus {
        get {
            lock.withLock { state }
        }
        set {
            lock.withLock { state = newValue }
        }
    }

    static func setNeedsMigration() {
        lock.withLock {
            if state == .initial {
                state = .pending
            }
        }
    }

    static func beginMigrationIfNeeded() -> Bool {
        lock.withLock {
            if state != .pending {
                return false
            }
            state = .started
            return true
        }
    }

    static func isMigrationInProgress() -> Bool {
        lock.withLock {
            state == .pending || state == .started
        }
    }

    static func markMigrationDone() {
        lock.withLock {
            state = .done
        }
    }
}
