// Core/Helpers/Lock+Windows.swift
/*
 Lock (Lock.swift) on Windows, which has no pthreads: a slim reader/writer lock (SRWLOCK), used
 exclusively. It needs only the Windows API, as the pthread one needs only the C library.

 The SRWLOCK lives in allocated memory, not in a stored property: it may not move once in use, and
 Swift may move a stored value.
*/

#if os(Windows)

import WinSDK

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

#endif
