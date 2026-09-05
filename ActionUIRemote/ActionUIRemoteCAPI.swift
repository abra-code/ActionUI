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

/// The token `actionUIRemoteStartServer` minted, or NULL when it required none.
///
/// Captured at start, so it survives `actionUIRemoteUnexportToken()` and is the only way to read
/// the start-up token afterwards. It is also the only exact way to read it at any time: a
/// language runtime that snapshots the environment at startup - CPython does - never sees a
/// setenv made afterwards, and anything it builds from that snapshot would hand a child an
/// environment with no token in it.
///
/// This does not report the tokens `actionUIRemoteMintToken` and `actionUIRemoteAddToken`
/// register; a host that mints per unit of work already holds those.
///
/// Same lifetime rule as `actionUIRemoteServerEndpoint`: owned by this target, valid until the
/// next start or stop, copy it if you keep it.
@_cdecl("actionUIRemoteServerToken")
public func actionUIRemoteServerToken() -> UnsafePointer<CChar>? {
    tokenLock.lock()
    defer { tokenLock.unlock() }
    return tokenCString.map { UnsafePointer($0) }
}

/// The same token, copied into the caller's buffer under the lock.
///
/// Prefer this to `actionUIRemoteServerToken` from any host that can stop the server on one
/// thread while another asks for the token. That accessor hands back the pointer it owns and
/// releases the lock before the caller can read through it, so a concurrent
/// `actionUIRemoteStopServer` - which frees that buffer - leaves the reader holding freed
/// memory. The window is small and the shape is the same as `actionUIRemoteServerEndpoint`'s,
/// but the language bindings run exactly that way: `ActionUIPython` documents starting and
/// stopping the server from a worker thread and releases the GIL across the stop.
///
/// - Parameters:
///   - outToken: where to write the NUL-terminated token. Nothing is written on failure.
///   - outTokenSize: the buffer's size in bytes. 128 is always enough; the token is 65 bytes
///     today, and a buffer smaller than the token is a failure, never a truncation.
/// - Returns: false when no token is held, or the buffer is missing or too small.
@_cdecl("actionUIRemoteCopyServerToken")
public func actionUIRemoteCopyServerToken(_ outToken: UnsafeMutablePointer<CChar>?,
                                          _ outTokenSize: Int) -> CBool {
    guard let outToken, outTokenSize > 0 else { return false }
    tokenLock.lock()
    defer { tokenLock.unlock() }
    guard let token = tokenCString else { return false }
    let length = strlen(token)
    guard length + 1 <= outTokenSize else { return false }
    memcpy(outToken, token, length + 1)
    return true
}

// MARK: - Per-unit-of-work tokens

/// The buffer `actionUIRemoteMintToken` needs: 64 hex characters and a terminator, rounded up so
/// that a caller sizing a fixed array does not have to track the encoding.
private let mintedTokenBufferSize = 128

/// Mint a token, register it under `label`, and copy it into the caller's buffer.
///
/// This is the entry point a host that spawns work wants: one grant per unit of work, withdrawn
/// with `actionUIRemoteRevokeTokensWithLabel` when that work ends. The token is minted here
/// rather than by the caller so that one CSPRNG and one encoding serve every host - see
/// `ActionUIRemoteServer.makeToken()`, which is what this calls.
///
/// - Parameters:
///   - label: what `actionUIRemoteRevokeTokensWithLabel` matches on - a command id, say. NULL or
///     empty is rejected, because a grant nothing can name is a grant nothing can withdraw.
///   - outToken: where to write the NUL-terminated token. Nothing is written on failure.
///   - outTokenSize: the buffer's size in bytes. 128 is always enough; the token is 65 bytes
///     today and a smaller buffer than the token needs is a failure, never a truncation.
/// - Returns: false when no server is running, when the label is empty, or when the buffer is
///   too small.
///
/// The token is deliberately not returned as a pointer this target owns: many are live at once,
/// so a process-wide cached string would be the wrong shape.
@_cdecl("actionUIRemoteMintToken")
public func actionUIRemoteMintToken(_ label: UnsafePointer<CChar>?,
                                    _ outToken: UnsafeMutablePointer<CChar>?,
                                    _ outTokenSize: Int) -> CBool {
    guard let outToken, outTokenSize > 0 else { return false }
    guard let label, strlen(label) > 0 else { return false }
    guard let server = ActionUIRemoteServer.shared else { return false }

    let token = ActionUIRemoteServer.makeToken()
    let bytes = Array(token.utf8)
    guard bytes.count + 1 <= outTokenSize else { return false }

    server.addToken(token, label: String(cString: label))
    bytes.withUnsafeBufferPointer { source in
        outToken.withMemoryRebound(to: UInt8.self, capacity: bytes.count + 1) { destination in
            destination.update(from: source.baseAddress!, count: bytes.count)
            destination[bytes.count] = 0
        }
    }
    return true
}

/// Register a token the caller minted, under `label`.
///
/// Prefer `actionUIRemoteMintToken`, which mints and registers in one step; this exists for a
/// host that must generate the value itself. Empty tokens and empty labels are rejected.
///
/// - Returns: false when no server is running, or either argument is missing or empty.
@_cdecl("actionUIRemoteAddToken")
public func actionUIRemoteAddToken(_ token: UnsafePointer<CChar>?,
                                   _ label: UnsafePointer<CChar>?) -> CBool {
    guard let token, strlen(token) > 0 else { return false }
    guard let label, strlen(label) > 0 else { return false }
    guard let server = ActionUIRemoteServer.shared else { return false }
    server.addToken(String(cString: token), label: String(cString: label))
    return true
}

/// Withdraw every token registered under `label`. Does nothing when no server is running, or
/// when no token carries that label.
///
/// Revocation stops new connections; it does not tear down authenticated ones (PROTOCOL.md
/// section 10). A host that needs the stronger property stops the server.
@_cdecl("actionUIRemoteRevokeTokensWithLabel")
public func actionUIRemoteRevokeTokensWithLabel(_ label: UnsafePointer<CChar>?) {
    guard let label, strlen(label) > 0 else { return }
    ActionUIRemoteServer.shared?.revokeTokens(label: String(cString: label))
}

/// Turn the token requirement on or off on the running server.
///
/// `actionUIRemoteStartServer` turns it on and mints one token, so a host that mints per unit of
/// work does not need this. It is here for a host that wants the requirement off - a test
/// harness, say - or that wants to turn it on after registering its own tokens.
///
/// - Returns: false when no server is running, in which case nothing was changed.
@_cdecl("actionUIRemoteSetRequiresToken")
public func actionUIRemoteSetRequiresToken(_ required: CBool) -> CBool {
    guard let server = ActionUIRemoteServer.shared else { return false }
    server.requiresToken = required
    return true
}

/// Remove `ACTIONUI_REMOTE_TOKEN` from this process's environment, so that nothing spawned
/// afterwards inherits it.
///
/// A host that hands each child its own token on a descriptor calls this immediately after
/// `actionUIRemoteStartServer` succeeds. The reason it must: a child's environment is built from
/// the host's, and a `python3` or `node` child's exec-time environment is readable by any
/// same-uid process through `ps` (PROTOCOL.md section 10). Keeping the token out of `envp`
/// entirely is the only thing that helps; clearing it inside the child does not, because `ps`
/// reads a snapshot frozen at exec.
///
/// The start-up token itself stays valid and stays readable through
/// `actionUIRemoteServerToken()` - this is about the environment, not about the grant. A host
/// that wants it withdrawn as well calls `actionUIRemoteRevokeTokensWithLabel("host")`.
///
/// - Returns: true when the variable was set and has been removed, false when there was nothing
///   to remove.
@_cdecl("actionUIRemoteUnexportToken")
public func actionUIRemoteUnexportToken() -> CBool {
    guard getenv(ActionUIRemoteEnvironment.token) != nil else { return false }
    unsetenv(ActionUIRemoteEnvironment.token)
    return true
}

/// True while the process-wide server is serving. Convenience for a host that only wants to
/// know whether to start one.
@_cdecl("actionUIRemoteServerIsRunning")
public func actionUIRemoteServerIsRunning() -> CBool {
    return ActionUIRemoteServer.shared != nil
}

#endif
