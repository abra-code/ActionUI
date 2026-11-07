// ActionUIRemote/ActionUIRemoteCAPI.swift
//
// The C face of the process-wide server, for hosts that are not Swift. OMC is Objective-C++ and
// links this target directly; `ActionUIRemoteServer` is a plain Swift class, so none of its API
// is visible through a generated ObjC header. These @c functions are: their declarations
// appear in ActionUIRemote-Swift.h, for plain C, C++ and Objective-C alike. That generated
// header is their only C declaration (they use no C types of their own, so there is no
// hand-written header); Scripts/check-c-prototypes.sh --generated-headers checks that plain C
// sees every one.
//
// Swift hosts should call ActionUIRemoteServer.startShared and friends instead; this is a
// wrapper over exactly that, with C strings and a bool in place of throws.
//
// Bool: all @c functions use Swift's CBool (= stdbool.h bool).

#if os(macOS) || os(Linux)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Dispatch
import ActionUI

// MARK: - The endpoint as a C string

/// A stable copy of the running server's path, because a `@c` function cannot hand back a
/// Swift String. Guarded by its own lock, and nothing is called out to while holding it.
private nonisolated(unsafe) var endpointCString: UnsafeMutablePointer<CChar>?
private let endpointLock = Lock()

private nonisolated(unsafe) var tokenCString: UnsafeMutablePointer<CChar>?
private let tokenLock = Lock()

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
    guard isMainThread else { return nil }
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
    if isMainThread {
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
@c
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
@c
public func actionUIRemoteStopServer() {
    ActionUIRemoteServer.stopShared()
    setEndpointCString(nil)
    setTokenCString(nil)
}

/// The socket path of the running server, or NULL when none is running.
///
/// The returned string is owned by this target and stays valid until the next
/// `actionUIRemoteStartServer` or `actionUIRemoteStopServer`; copy it if you keep it.
@c
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
@c
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
@c
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
@c
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
@c
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
@c
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
@c
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
@c
public func actionUIRemoteUnexportToken() -> CBool {
    guard getenv(ActionUIRemoteEnvironment.token) != nil else { return false }
    unsetenv(ActionUIRemoteEnvironment.token)
    return true
}

/// True while the process-wide server is serving. Convenience for a host that only wants to
/// know whether to start one.
@c
public func actionUIRemoteServerIsRunning() -> CBool {
    return ActionUIRemoteServer.shared != nil
}

// MARK: - Host extension methods

/// A host method written in C, the C form of `ActionUIRemoteServer.Handler` (PROTOCOL.md
/// section 8).
///
/// Called on the main thread, once per request, while the client's connection waits for the
/// answer, so it must return promptly: the connection gives up after the server's main-thread
/// timeout and answers 1005. A host that has to wait for something answers "not yet" and lets
/// the client ask again. It must not stop the server from inside the call, and a C++ host must
/// not let an exception leave it: it returns into Swift, where unwinding is undefined.
///
/// - Parameters:
///   - context: the pointer passed to `actionUIRemoteRegisterMethod`, unchanged.
///   - method: the method's name, so one function can serve several.
///   - paramsJSON: the request's named params as a JSON object in UTF-8, `{}` when it had none,
///     with the reserved `token` key already removed (PROTOCOL.md section 10).
/// - Returns: the answer as JSON text in a buffer from `malloc`, which this target frees: an
///   object with either a `result` member, any JSON value, or an `error` member, an object with
///   an integer `code` and a string `message`, as in a JSON-RPC reply. NULL, text that is not
///   JSON or an object with neither member answers -32603 (internal error), and the host's
///   mistake is logged.
public typealias ActionUIRemoteMethodCallback = @convention(c) (
    _ context: UnsafeMutableRawPointer?,
    _ method: UnsafePointer<CChar>,
    _ paramsJSON: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar>?

/// A C host method and its context, carried into the registry's main-actor closure. The context
/// is the host's to keep alive and thread-safe; this target only hands it back, on the main
/// thread, which is where the host registered it to be used.
private struct CHostMethod: @unchecked Sendable {
    let callback: ActionUIRemoteMethodCallback
    let context: UnsafeMutableRawPointer?
}

/// Whether `name` may be registered or unregistered through the C entry points: namespaced, with
/// something on both sides of the first dot, and not in the reserved `actionui.` namespace, so a
/// host cannot replace or remove a built-in method this way.
private func isHostMethodName(_ name: String) -> Bool {
    guard let dot = name.firstIndex(of: "."), dot != name.startIndex,
          name.index(after: dot) != name.endIndex else {
        return false
    }
    return name[name.startIndex..<dot] != "actionui"
}

/// The reply a C host method returned, turned into what a Swift handler returns or throws.
@MainActor
private func hostMethodOutcome(_ reply: UnsafeMutablePointer<CChar>?, method: String) throws -> Any? {
    func malformed(_ problem: String) -> ActionUIRemoteError {
        ActionUIModel.shared.logger.log("ActionUIRemote: host method \(method) \(problem)", .error)
        return ActionUIRemoteError(code: ActionUIRemoteError.internalError,
                                   message: "Internal error: host method \(method) \(problem)")
    }

    guard let reply else {
        throw malformed("returned no reply")
    }
    let text = String(cString: reply)
    free(reply)

    let object: [String: Any]
    do {
        guard let parsed = try ActionUIJSON.value(from: text) as? [String: Any] else {
            throw malformed("returned JSON that is not an object")
        }
        object = parsed
    } catch let error as ActionUIRemoteError {
        throw error
    } catch {
        throw malformed("returned text that is not JSON: \(error)")
    }

    if let errorObject = object["error"] {
        guard let fields = errorObject as? [String: Any],
              let code = fields["code"] as? Int,
              let message = fields["message"] as? String else {
            throw malformed("returned an error without an integer code and a string message")
        }
        throw ActionUIRemoteError(code: code, message: message, data: fields["data"])
    }
    guard object.keys.contains("result") else {
        throw malformed("returned an object with neither result nor error")
    }
    // ActionUIJSON reads null as ActionUIJSONNull, which the encoder writes back as null.
    return object["result"]
}

/// Register a method written in C on the running server, or replace one registered earlier
/// under the same name. This is `ActionUIRemoteServer.register(method:handler:)` for a host
/// that is not Swift.
///
/// The method lives as long as the server: `actionUIRemoteStopServer` drops it with everything
/// else, and a host that starts the server again registers it again.
///
/// - Parameters:
///   - method: the name, in the host's own namespace (`omc.test.status`). Names in the reserved
///     `actionui.` namespace, and names without a namespace, are refused.
///   - callback: the implementation; see `ActionUIRemoteMethodCallback`.
///   - context: handed back to every call, never read or freed here. It must stay valid until
///     the method is unregistered or the server stops. Done on the main thread, that is as soon
///     as the call returns; done from another thread, a call may already be running or queued,
///     so only once the main queue has run after it.
/// - Returns: false when no server is running, the name is refused, or the callback is NULL;
///   nothing was registered in that case.
///
/// Safe from any thread. From the main thread the method is callable as soon as this returns;
/// from another thread, from the next main-queue turn.
@c
public func actionUIRemoteRegisterMethod(_ method: UnsafePointer<CChar>?,
                                         _ callback: ActionUIRemoteMethodCallback?,
                                         _ context: UnsafeMutableRawPointer?) -> CBool {
    guard let method, let callback else { return false }
    let name = String(cString: method)
    guard isHostMethodName(name) else { return false }
    guard let server = ActionUIRemoteServer.shared else { return false }

    let hostMethod = CHostMethod(callback: callback, context: context)
    server.register(method: name) { [weak server] params in
        // A request queued for the main thread before a stop still runs after it; the host
        // may already have freed the context, so a stopped server never calls back.
        guard let server, ActionUIRemoteServer.shared === server else {
            throw ActionUIRemoteError(code: ActionUIRemoteError.internalError,
                                      message: "Internal error: the server stopped before \(name) ran")
        }
        let paramsText: String
        do {
            paramsText = try ActionUIJSON.string(from: params)
        } catch {
            throw ActionUIRemoteError(code: ActionUIRemoteError.internalError,
                                      message: "Internal error: the params could not be written as JSON: \(error)")
        }
        let reply = name.withCString { nameC in
            paramsText.withCString { paramsC in
                hostMethod.callback(hostMethod.context, nameC, paramsC)
            }
        }
        return try hostMethodOutcome(reply, method: name)
    }
    return true
}

/// Remove a method `actionUIRemoteRegisterMethod` registered. Built-in `actionui.` methods
/// cannot be removed this way.
///
/// - Returns: false when no server is running or the name is refused; true otherwise, also when
///   no method had that name.
///
/// Safe from any thread, with the same timing as registering.
@c
public func actionUIRemoteUnregisterMethod(_ method: UnsafePointer<CChar>?) -> CBool {
    guard let method else { return false }
    let name = String(cString: method)
    guard isHostMethodName(name) else { return false }
    guard let server = ActionUIRemoteServer.shared else { return false }
    server.unregister(method: name)
    return true
}

#endif
