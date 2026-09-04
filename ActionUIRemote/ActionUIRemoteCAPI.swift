// ActionUIRemote/ActionUIRemoteCAPI.swift
//
// The C face of the process-wide server, for hosts that are not Swift. OMC is Objective-C++ and
// links this target directly; `ActionUIRemoteServer` is a plain Swift class, so none of its API
// is visible through a generated ObjC header. These @_cdecl functions are, and their
// declarations appear in ActionUIRemote-Swift.h, the same arrangement ActionUICAdapter and
// ActionUIAppKitApplication use (their own headers carry types only).
//
// Swift hosts should call ActionUIRemoteServer.startShared and friends instead; this is a
// wrapper over exactly that, with C strings and a bool in place of throws.
//
// Bool: all @_cdecl functions use Swift's CBool (= stdbool.h bool).

#if os(macOS)

import Foundation
import ActionUI

// MARK: - The endpoint as a C string

/// A stable copy of the running server's path, because a `@_cdecl` function cannot hand back a
/// Swift String. Guarded by its own lock, and nothing is called out to while holding it.
private nonisolated(unsafe) var endpointCString: UnsafeMutablePointer<CChar>?
private let endpointLock = NSLock()

private nonisolated(unsafe) var tokenCString: UnsafeMutablePointer<CChar>?
private let tokenLock = NSLock()

private func setTokenCString(_ token: String?) {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    free(tokenCString)
    tokenCString = token.map { strdup($0) } ?? nil
}

private func setEndpointCString(_ path: String?) {
    endpointLock.lock()
    defer { endpointLock.unlock() }
    free(endpointCString)
    endpointCString = path.map { strdup($0) } ?? nil
}

// MARK: - Diagnostics

/// The engine's logger, but only when it costs nothing: `ActionUIModel` is main-actor isolated,
/// and a synchronous hop to fetch it would hang whenever the main queue is not being serviced -
/// a worker thread starting the server before the app runs is exactly that case.
private func engineLoggerIfFree() -> (any ActionUILogger)? {
    guard Thread.isMainThread else { return nil }
    return MainActor.assumeIsolated { ActionUIModel.shared.logger }
}

/// Give the running server the engine's logger without blocking the caller.
private func attachEngineLoggerAsync() {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            ActionUIRemoteServer.shared?.logger = ActionUIModel.shared.logger
        }
    }
}

/// Report through the engine's logger from any thread, without blocking.
private func logToEngine(_ message: String, _ level: LoggerLevel) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { ActionUIModel.shared.logger.log(message, level) }
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { ActionUIModel.shared.logger.log(message, level) }
        }
    }
}

// MARK: - Entry points

/// Start the process-wide server and export `ACTIONUI_REMOTE_ENDPOINT`, so that processes
/// spawned afterwards inherit it. Read the bound path back with `actionUIRemoteServerEndpoint()`.
///
/// - Parameters:
///   - socketPath: where to bind; NULL takes a per-process default in the user's temporary
///     directory. **Anything already at the path is unlinked first**, so pass a path of your own
///     making, not a file that matters.
///   - hostName: how to answer `actionui.hello`; NULL takes the running process's name.
///   - hostVersion: likewise; NULL takes the bundle's version, or "0".
/// - Returns: false if a server is already running or the socket could not be created. The
///   reason is logged through `ActionUIModel.shared.logger`.
///
/// Safe to call from any thread, with or without a run loop: nothing here waits on the main
/// queue. A caller holding a language runtime's global lock must release it first, because
/// starting logs and the log goes back through that runtime's callback.
@_cdecl("actionUIRemoteStartServer")
public func actionUIRemoteStartServer(_ socketPath: UnsafePointer<CChar>?,
                                      _ hostName: UnsafePointer<CChar>?,
                                      _ hostVersion: UnsafePointer<CChar>?) -> CBool {
    let path = socketPath.map { String(cString: $0) }
    var host = ActionUIRemoteServer.currentProcessHost()
    if let hostName {
        host.name = String(cString: hostName)
    }
    if let hostVersion {
        host.version = String(cString: hostVersion)
    }

    let logger = engineLoggerIfFree()
    do {
        let bound = try ActionUIRemoteServer.startShared(socketPath: path, host: host, logger: logger)
        setEndpointCString(bound)
        setTokenCString(getenv(ActionUIRemoteEnvironment.token).map { String(cString: $0) })
        if logger == nil {
            attachEngineLoggerAsync()
        }
        return true
    } catch {
        logToEngine("actionUIRemoteStartServer: could not start on "
                    + "'\(path ?? ActionUIRemoteServer.defaultSocketPath())': \(error)", .error)
        return false
    }
}

/// Stop the process-wide server, close its connections, remove its socket file, and unset
/// `ACTIONUI_REMOTE_ENDPOINT`. Does nothing when none is running, and never unsets a variable
/// this process did not set. Safe to call from any thread, with the same caveat about a
/// runtime's global lock as `actionUIRemoteStartServer`.
@_cdecl("actionUIRemoteStopServer")
public func actionUIRemoteStopServer() {
    ActionUIRemoteServer.stopShared()
    setEndpointCString(nil)
    setTokenCString(nil)
}

/// The socket path of the running server, or NULL when none is running.
///
/// The returned string is owned by this target and stays valid until the next
/// `actionUIRemoteStartServer` or `actionUIRemoteStopServer`; copy it if you keep it.
@_cdecl("actionUIRemoteServerEndpoint")
public func actionUIRemoteServerEndpoint() -> UnsafePointer<CChar>? {
    endpointLock.lock()
    defer { endpointLock.unlock() }
    return endpointCString.map { UnsafePointer($0) }
}

/// The token the running server requires, or NULL when it requires none.
///
/// The value is also in the process environment, but a binding cannot always read it there: a
/// language runtime that snapshots the environment at startup - CPython does - never sees a
/// setenv made afterwards, and anything it builds from that snapshot would hand a child an
/// environment with no token in it. Reading it here is exact.
///
/// Same lifetime rule as `actionUIRemoteServerEndpoint`: owned by this target, valid until the
/// next start or stop, copy it if you keep it.
@_cdecl("actionUIRemoteServerToken")
public func actionUIRemoteServerToken() -> UnsafePointer<CChar>? {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    return tokenCString.map { UnsafePointer($0) }
}

/// True while the process-wide server is serving. Convenience for a host that only wants to
/// know whether to start one.
@_cdecl("actionUIRemoteServerIsRunning")
public func actionUIRemoteServerIsRunning() -> CBool {
    return ActionUIRemoteServer.shared != nil
}

#endif
