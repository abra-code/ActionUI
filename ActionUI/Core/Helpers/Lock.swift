// Core/Helpers/Lock.swift
/*
 A mutual-exclusion lock, for state that more than one thread may touch: a pthread mutex on Apple
 platforms and Linux, a slim reader/writer lock (SRWLOCK, used exclusively) on Windows. Foundation's
 NSLock would do on Apple, but this file needs only the C library (on Windows, the Windows API), so
 the core does not depend on full Foundation for it. (The standard library's Mutex would serve
 everywhere, but needs macOS 15.)

 The lock lives in allocated memory, not in a stored property: neither a pthread mutex nor an
 SRWLOCK may move once in use, and Swift may move a stored value.
*/

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import WinSDK
#endif

#if os(Windows)
final class Lock: @unchecked Sendable {
    private let srwLock: UnsafeMutablePointer<SRWLOCK>

    init() {
        srwLock = UnsafeMutablePointer<SRWLOCK>.allocate(capacity: 1)
        InitializeSRWLock(srwLock)
    }

    deinit {
        // An SRWLOCK holds no resources: nothing to destroy.
        srwLock.deallocate()
    }

    /// Runs `body` while holding the lock. Not reentrant: `body` must not take the same lock.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        AcquireSRWLockExclusive(srwLock)
        defer { ReleaseSRWLockExclusive(srwLock) }
        return try body()
    }
}
#else
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
#endif
