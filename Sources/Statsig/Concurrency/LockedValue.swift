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

 3. This does support mutating operations on structs and values. Normally
    they'd be considered separate get and set operations, but thanks to
    `_modify`, Swift hold the lock for the operation. Examples:

    @LockedValue var dict: [String: Int] = [:]
    @LockedValue var size: Double = 0

    dict.removeValue(forKey: "foo") // OK
    size += 1 // OK
    size = size + 1 // LOCKED TWICE! Use `$size.withLock { ... }` instead
    size = pow(size, 2) // LOCKED TWICE! Use `$size.withLock { ... }` instead

 4. IMPORTANT: Accessing multiple times doesn't keep the lock, and could result
    in race conditions:

    @LockedValue var counts: [String: Int] = [:]
    let snapshot = counts // uses a lock to read
    counts.removeAll() // uses a lock to write
    // counts could've changed between the write and the read by another thread

 5. IMPORTANT: Don't use the locked property from inside `.withLock { ... }`:


    @LockedValue var counts: [String: Int] = [:]

    let pending = $counts.withLock { counts in
        let snapshot = counts
        self.counts.removeAll() // Deadlock!
        // The line above should access `counts` (parameter),
        // not `self.counts` (property)

        return snapshot
    }

 6. If you have a great reason to access the value without a lock:

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
final class LockedValue<Value> {

    var projectedValue: LockedValue {
        self
    }

    private let lock = NSLock()

    var wrappedValue: Value {
        get { get() }
        set(v) { set(v) }
        _modify {
            lock.lock()
            defer { lock.unlock() }
            yield &unsafeValue
        }
    }

    var unsafeValue: Value

    init(wrappedValue: Value) {
        unsafeValue = wrappedValue
    }

    func withLock<R>(_ body: (_ value: inout Value) throws -> R) rethrows -> R {
        try lock.withLock {
            return try body(&unsafeValue)
        }
    }

    func get() -> Value {
        lock.withLock {
            return unsafeValue
        }
    }

    func set(_ v: Value) {
        lock.withLock {
            unsafeValue = v
        }
    }
}
