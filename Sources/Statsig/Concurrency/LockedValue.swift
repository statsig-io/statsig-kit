import Foundation

/**

 Wraps mutable properties with a lock to reduce concurrency issues.

 PLEASE READ THIS COMMENT BLOCK TO LEARN ABOUT EDGE CASES!

 1. Plain reads and writes are safe:

    @LockedValue var user: StatsigUser
    let currentUser = user
    user = newUser

 2. Use `$property.withLock` to hold the lock for multiple operations:

    @LockedValue var counts: [String: Int] = [:]

    $counts.withLock { counts in
        // Update the value of the function parameter (not the property)
        counts["gate", default: 0] += 1
    }

    let pending = $counts.withLock { counts in
        let snapshot = counts
        counts.removeAll()
        return snapshot
    }

 3. IMPORTANT: Accessing multiple times doesn't keep the lock, and could result
    in race conditions:

    @LockedValue var counts: [String: Int] = [:]
    let snapshot = counts // uses a lock to read
    counts.removeAll() // uses a lock to write
    // counts could've changed between the write and the read by another thread

 4. IMPORTANT: Don't use the locked property from inside `.withLock { ... }`:


    @LockedValue var counts: [String: Int] = [:]

    let pending = $counts.withLock { counts in
        let snapshot = counts
        self.counts.removeAll() // Deadlock!
        // The line above should access `counts` (parameter),
        // not `self.counts` (property)

        return snapshot
    }

 5. If you have a great reason to access the value without a lock:

    @LockedValue var user: StatsigUser
    let currentUser = $user.unsafeValue // Avoid this pattern!

 If we're running into the edge cases outlined above, we should stop
 using @propertyWrapper, and migrate to a wrapper type instead. example:

    var user: Locked<StatsigUser>
    let currentUser = user.get()
    user.set(...)
    user.withLock { ... }

 */
@propertyWrapper
struct LockedValue<Value> {

    var projectedValue: LockedValue {
        get { self }
        _modify { yield &self }
    }

    private let lock = NSLock()

    var wrappedValue: Value {
        get {
            return lock.withLock {
                return unsafeValue
            }
        }
        set(v) {
            lock.withLock {
                self.unsafeValue = v
            }
        }
    }

    var unsafeValue: Value

    init(wrappedValue: Value) {
        self.unsafeValue = wrappedValue
    }

    mutating func withLock<R>(_ body: (_ value: inout Value) throws -> R) rethrows -> R {
        try lock.withLock {
            try body(&unsafeValue)
        }
    }

    func get() -> Value {
        return self.wrappedValue
    }

    mutating func set(_ v: Value) {
        self.wrappedValue = v
    }
}
