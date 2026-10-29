// ActionUIRemote/RemoteSupport.swift
//
// What the remote binding needs from the platform beyond Swift and Dispatch, written against the
// C library so the same code serves every platform: a lock (Foundation's NSLock is not in
// FoundationEssentials) and the main-thread test (nor is Foundation's Thread).

#if os(macOS)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Dispatch

/// A mutual-exclusion lock over a pthread mutex. Not reentrant. The mutex lives in allocated
/// memory, not in a stored property: a pthread mutex must not move once initialized, and Swift
/// may move a stored value. (Core has the same lock, internal to the ActionUI module.)
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

    func lock() {
        pthread_mutex_lock(mutex)
    }

    func unlock() {
        pthread_mutex_unlock(mutex)
    }
}

// The main queue carries this key, and the main thread runs with the main queue as its current
// queue except inside another queue's work, so the key is present on the main thread and absent on
// any other: the test the C adapter uses (ActionUICAdapter/ActionUIC.swift). The one difference
// from Thread.isMainThread: a call made inside a block the main thread runs for another queue
// (DispatchQueue.global().sync from the main thread) counts as off the main thread, which only
// sends the work through the main queue instead of running it at once.
private let mainQueueKey: DispatchSpecificKey<Bool> = {
    let key = DispatchSpecificKey<Bool>()
    DispatchQueue.main.setSpecific(key: key, value: true)
    return key
}()

/// Whether the caller runs on the main thread, as the main queue sees it.
var isMainThread: Bool {
    DispatchQueue.getSpecific(key: mainQueueKey) == true
}

#endif
