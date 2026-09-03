// ActionUIRemote/ActionUIRemoteSharedServer.swift
//
// The process-wide server: one endpoint per process, which is the shape PROTOCOL.md section 9
// describes. Every host that spawns children wants exactly this - a singleton, a default socket
// path, and ACTIONUI_REMOTE_ENDPOINT in the environment - and this is where it lives so that the
// hosts do not each write their own and drift. OMC links this target and nothing else; the
// AppKit application adapter wraps these in @_cdecl entry points for its Python and Node
// bindings. Neither owns the lifecycle.
//
// A host with different needs (two servers, no environment export, a path of its own) builds an
// ActionUIRemoteServer directly. Nothing here is required to use the target.

#if os(macOS)

import Foundation
import ActionUI

/// Process-wide state. A final class with its own lock rather than globals, so Swift 6 sees one
/// Sendable box instead of mutable global state.
private final class SharedServerStorage: @unchecked Sendable {
    let lock = NSLock()
    var server: ActionUIRemoteServer?       // guarded by lock
    var starting = false                    // guarded by lock
}

private let sharedStorage = SharedServerStorage()

/// The path the atexit handler unlinks. Written under the lock, read without one: by the time
/// the handler runs the process is on its way out. `nil` when no shared server is running.
private nonisolated(unsafe) var atexitSocketPath: UnsafeMutablePointer<CChar>?
private nonisolated(unsafe) var atexitRegistered = false

/// Last resort: `NSApplication.terminate` ends in libc `exit()`, and so does any host that calls
/// it directly, which runs neither a Swift `defer` nor a Python `atexit` nor a Node `exit` event.
/// Only unlinks; closing connections properly is the job of the host's termination hook.
private func unlinkSharedSocketAtExit() {
    if let path = atexitSocketPath {
        unlink(path)
    }
}

public extension ActionUIRemoteServer {

    // MARK: - Host identity

    /// How the running process names itself when the host has nothing better: the bundle's
    /// name, or the process name, with the bundle's version when there is one.
    static func currentProcessHost() -> HostInfo {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "0"
        return HostInfo(name: name, version: version)
    }

    // MARK: - The process-wide server

    /// The socket path `startShared` binds when the caller does not choose one: one per process,
    /// in the user's private temporary directory. Short on purpose, because `sun_path` holds
    /// 103 bytes and a long `TMPDIR` leaves little room.
    static func defaultSocketPath() -> String {
        return (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("actionui-\(getpid()).sock")
    }

    /// The process-wide server, or nil when none is running. This is where a host registers its
    /// own methods: `ActionUIRemoteServer.shared?.register(method: "omc.terminate") { ... }`.
    static var shared: ActionUIRemoteServer? {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        return sharedStorage.server
    }

    /// The socket path the shared server is serving, or nil when none is running.
    static var sharedEndpoint: String? {
        return shared?.endpoint
    }

    /// Start the process-wide server and export its path as `ACTIONUI_REMOTE_ENDPOINT`, so that
    /// processes spawned afterwards inherit it and a client finds the host with no configuration.
    ///
    /// - Parameters:
    ///   - socketPath: where to bind; `nil` takes `defaultSocketPath()`. **Anything already at
    ///     the path is unlinked first**, so give a path of your own making, not a file that
    ///     matters.
    ///   - host: how to answer `actionui.hello`. Defaults to the running process.
    ///   - logger: where the server's diagnostics go. Nil is silent.
    /// - Returns: the path that was bound, which is what a caller who passed nil wants to know.
    /// - Throws: `UnixSocketServerError.alreadyStarted` when a shared server is already running,
    ///   and whatever `start(socketPath:)` throws (a path over `sun_path`, a failed bind).
    ///
    /// The socket file outlives a process that exits without stopping the server, so a host
    /// should call `stopShared()` from its termination hook. Failing that, an `atexit` handler
    /// registered here unlinks the socket, which covers a host that ends in `exit()`.
    ///
    /// Safe to call from any thread, and it calls out to the logger only outside its own lock.
    @discardableResult
    static func startShared(socketPath: String? = nil,
                            host: HostInfo = currentProcessHost(),
                            logger: (any ActionUILogger)? = nil) throws -> String {
        let path = socketPath ?? defaultSocketPath()

        // Claim the start under the lock, then build and bind outside it: `start` logs, and a
        // host's logger callback may well ask this type a question (`sharedEndpoint`), which a
        // non-recursive lock held across the call-out would deadlock. Same discipline as
        // ActionUIRemoteServer.start and UnixSocketServer.start one layer down.
        sharedStorage.lock.lock()
        let claimed = !sharedStorage.starting && sharedStorage.server == nil
        if claimed {
            sharedStorage.starting = true
        }
        sharedStorage.lock.unlock()
        guard claimed else {
            throw UnixSocketServerError.alreadyStarted
        }

        let server = ActionUIRemoteServer(host: host)
        server.logger = logger
        do {
            try server.start(socketPath: path)
        } catch {
            sharedStorage.lock.lock()
            sharedStorage.starting = false
            sharedStorage.lock.unlock()
            throw error
        }

        sharedStorage.lock.lock()
        sharedStorage.server = server
        sharedStorage.starting = false
        free(atexitSocketPath)
        atexitSocketPath = strdup(path)
        if !atexitRegistered {
            atexitRegistered = true
            atexit(unlinkSharedSocketAtExit)
        }
        sharedStorage.lock.unlock()

        setenv(ActionUIRemoteEnvironment.endpoint, path, 1)
        return path
    }

    /// Stop the process-wide server, close its connections, remove its socket file, and unset
    /// `ACTIONUI_REMOTE_ENDPOINT`. Does nothing when none is running, and never unsets a
    /// variable this process did not set. Safe to call from any thread.
    static func stopShared() {
        sharedStorage.lock.lock()
        let server = sharedStorage.server
        sharedStorage.server = nil
        free(atexitSocketPath)
        atexitSocketPath = nil
        sharedStorage.lock.unlock()

        guard let server else { return }        // nothing of ours is running: leave the environment alone
        server.stop()                           // outside the lock: stop logs
        unsetenv(ActionUIRemoteEnvironment.endpoint)
    }
}

/// The environment contract of PROTOCOL.md section 9, named once so that hosts and tests agree.
public enum ActionUIRemoteEnvironment {
    /// The absolute socket path of the host's server.
    public static let endpoint = "ACTIONUI_REMOTE_ENDPOINT"
    /// The window a child process was started for, when there is one. Set by the host, not here:
    /// only the host knows which window a given child is about.
    public static let windowUUID = "ACTIONUI_WINDOW_UUID"
}

#endif
