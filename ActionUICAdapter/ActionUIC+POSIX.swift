// ActionUICAdapter/ActionUIC+POSIX.swift
//
//  The C library parts of the adapter on Apple platforms and Linux: the heap copy every string
//  result is (strdup), and the per-thread slot that holds the last error (a pthread key). Windows,
//  which has no pthreads, has its own (ActionUIC+Windows.swift). Compiled by the Apple and the Linux
//  ActionUICAdapter targets (Package.swift).
//

#if !os(Windows)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Heap-copy `str` into a malloc-owned C string. Caller must free with actionUIFreeString.
@inline(__always)
func actionStrdup(_ str: String) -> UnsafeMutablePointer<CChar>? {
    return str.withCString { strdup($0) }
}

// MARK: - The last error's per-thread slot (ActionUIC.swift's lastError)

private let lastErrorKey: pthread_key_t = {
    var key = pthread_key_t()
    // The destructor's parameter is optional in Glibc's declaration and not in Darwin's; a call
    // through releaseLastError, which takes an optional, fits both.
    let status = pthread_key_create(&key) { releaseLastError($0) }
    precondition(status == 0, "ActionUI C adapter: pthread_key_create failed (\(status))")
    return key
}()

/// The calling thread's slot: a retained LastError, or nil when there is no error.
func lastErrorSlot() -> UnsafeMutableRawPointer? {
    pthread_getspecific(lastErrorKey)
}

/// Sets the calling thread's slot; false when the C library cannot allocate it.
func setLastErrorSlot(_ slot: UnsafeMutableRawPointer?) -> Bool {
    pthread_setspecific(lastErrorKey, slot) == 0
}

#endif
