// Helpers/Lock.swift
/*
 A mutual-exclusion lock over a pthread mutex, for state that more than one thread may touch.
 Foundation's NSLock would do on Apple, but this file needs only the C library, so the same lock
 serves every platform.

 The mutex lives in allocated memory, not in a stored property: a pthread mutex must not move
 once initialized, and Swift may move a stored value.
*/

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

final class Lock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    init() {
        mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize(count: 1)
        mutex.deallocate()
    }

    /// Runs `body` while holding the lock. Not reentrant: `body` must not take the same lock.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}
