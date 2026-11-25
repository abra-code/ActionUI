// ActionUIRemote/RemoteSupport+Windows.swift
//
// RemoteSupport.swift's platform parts on Windows, which has no pthreads and names some C library
// calls differently: the lock, a C string copy and the environment. The main-thread test is shared.

#if os(Windows)

import ucrt
import WinSDK

/// A copy of `text` in memory the caller frees with free(): the Windows C runtime names strdup
/// _strdup (and deprecates strdup).
func copyCString(_ text: String) -> UnsafeMutablePointer<CChar>? {
    return _strdup(text)
}

/// The environment variable `name` as the process holds it (what a child inherits), or nil when it
/// is not set.
func environmentValue(_ name: String) -> String? {
    return name.withCString(encodedAs: UTF16.self) { wideName -> String? in
        let needed = GetEnvironmentVariableW(wideName, nil, 0)
        guard needed > 0 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(needed))
        let written = GetEnvironmentVariableW(wideName, &buffer, needed)
        guard written > 0, written < needed else { return nil }
        return String(decoding: buffer[..<Int(written)], as: UTF16.self)
    }
}

/// Removes the environment variable `name` from this process's environment: from the C runtime's
/// copy and from the process's, which a child inherits (_wputenv_s with an empty value does both).
func removeEnvironmentValue(_ name: String) {
    name.withCString(encodedAs: UTF16.self) { wideName in
        [WCHAR(0)].withUnsafeBufferPointer { empty in
            _ = _wputenv_s(wideName, empty.baseAddress)
        }
    }
}

/// Whether `path` names a file from a drive's root: a drive letter, a colon and a slash (`C:\a.json`,
/// or `C:/a.json` as Foundation writes it). Not a network path (`\\server\share\...`, which would send
/// the user's sign-in to that server), a `\\.\` or `\\?\` path, a path from the current drive's root
/// (`\a.json`) or one relative to a drive's current folder (`C:a.json`). An old device name in a
/// folder (`C:\x\COM1`) and a drive letter mapped to a share pass, as they would for the client
/// itself; the caller reads only a regular file.
func isAbsoluteLocalPath(_ path: String) -> Bool {
    let units = Array(path.utf16.prefix(3))
    guard units.count == 3 else { return false }
    let letter = units[0]
    let isLetter = (letter >= 0x41 && letter <= 0x5A) || (letter >= 0x61 && letter <= 0x7A)
    return isLetter && units[1] == 0x3A && (units[2] == 0x5C || units[2] == 0x2F)
}

/// A mutual-exclusion lock over a slim reader/writer lock, used exclusively. Not reentrant. The
/// SRWLOCK lives in allocated memory: it may not move once in use, and Swift may move a stored value.
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

    func lock() {
        AcquireSRWLockExclusive(srwLock)
    }

    func unlock() {
        ReleaseSRWLockExclusive(srwLock)
    }
}

#endif
