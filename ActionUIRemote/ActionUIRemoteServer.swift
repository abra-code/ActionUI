// ActionUIRemote/ActionUIRemoteServer.swift
//
// The remote binding's server: a Unix domain socket speaking newline-delimited JSON-RPC 2.0,
// executing every request on the main actor against ActionUIModel.shared, with a registry that
// hosts extend with their own namespaced methods (OMC registers `omc.*`).
//
// Threading model (see PROTOCOL.md and the design note):
// - Lines arrive on the connection's serial queue. They are decoded there, wrapped in a
//   RequestBox, and handed to the main queue with DispatchQueue.main.async. The connection
//   queue then waits on the box's semaphore with a timeout, so a main thread that never comes
//   back (a bare system() call in the host) yields error 1005 instead of a hung client.
// - On the main queue the work runs inside MainActor.assumeIsolated. The closure captures only
//   the box (Sendable by construction: a lock around plain storage), never a request or a result.
// - Handlers are @MainActor closures stored in a @MainActor registry. A global-actor-isolated
//   function type is implicitly Sendable (SE-0434), so a handler can be handed to the main actor
//   from any thread even though its captures (host objects, [String: Any]) are not Sendable.
// - Results are made JSON-ready inside the main-actor block (ActionUIJSON), so nothing owned by
//   the engine is read off the main thread; only the envelope is serialized on the connection
//   queue.
// - Requests on one connection are strictly ordered (the wait happens on that connection's
//   queue); different connections interleave at request granularity on the main queue. A batch
//   is one main-queue block, so its members apply within one frame.

#if os(macOS)

import Foundation
import Security   // SecRandomCopyBytes, for makeToken()
import ActionUI

public final class ActionUIRemoteServer: @unchecked Sendable {

    /// Identifies the host in `actionui.hello`.
    public struct HostInfo: Sendable {
        public var name: String
        public var version: String

        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    /// A method implementation. Receives the request's named params (already JSON-decoded) and
    /// returns a JSON-ready result (`nil` encodes as null). Throw `ActionUIRemoteError` to answer
    /// with a specific code; any other error is reported as `hostRefused` (1004) with its
    /// description as the message.
    public typealias Handler = @MainActor (_ params: [String: Any]) throws -> Any?

    /// Resolves the `path` form of `actionui.presentModal` (a resource name or a relative path)
    /// to a file URL. Without a resolver only absolute paths are accepted.
    public typealias ModalResourceResolver = @MainActor (_ nameOrPath: String) -> URL?

    /// Bumped only for changes that break existing clients (a result shape, a removed method).
    public static let protocolVersion = 1

    public let host: HostInfo

    private let lock = NSLock()
    // Guarded by `lock`.
    private var _mainThreadTimeout: TimeInterval = 10
    private var _logger: (any ActionUILogger)?
    private var socketServer: UnixSocketServer?
    private var starting = false
    /// token -> label. Many are live at once: a host mints one per unit of work it spawns, so a
    /// grant can be withdrawn when that work ends without disturbing anything else.
    private var _tokens: [String: String] = [:]
    private var _requiresToken = false
    /// Connections that have already presented a valid token. A client may send it once and then
    /// stop, or send it on every request; both work.
    private var _authenticated: Set<UnixSocketServer.ConnectionID> = []

    /// Main-actor state: the method table and the modal resolver.
    let registry = MethodRegistry()

    // MARK: - Access control

    /// Whether a connection must present a valid token before it may call anything.
    ///
    /// Off by default, which is the historical behavior: the socket's own permissions and the
    /// peer-uid check are the boundary. A host turns it on so that a process it did not spawn,
    /// which therefore never received the token, cannot drive the UI merely by finding the
    /// socket - which it otherwise can, the path being no secret.
    ///
    /// This raises the cost of casual access; it does not stop a determined same-uid attacker.
    /// `ps eww` exposes the environment of a python3 or node process to any process of the same
    /// user - the kernel withholds it only for processes carrying the CS_RESTRICT code-signing
    /// flag (Apple platform/SIP binaries, setuid), which the interpreters the clients run under do
    /// not have - so a live handler's token is readable. See PROTOCOL.md section 10, which records
    /// the measurement. Same-uid has never been a boundary on macOS.
    public var requiresToken: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _requiresToken }
        set { lock.lock(); _requiresToken = newValue; lock.unlock() }
    }

    /// Mint nothing, register what the caller minted. The host owns token generation because it
    /// owns the lifetime: it knows when the work a token was issued for has finished.
    ///
    /// `label` is free-form and is what `revokeTokens(label:)` matches on - a command id, say, so
    /// a host can withdraw one command's grant without touching another's.
    public func addToken(_ token: String, label: String) {
        guard !token.isEmpty else { return }
        lock.lock()
        _tokens[token] = label
        lock.unlock()
    }

    /// Withdraw one token. Connections already authenticated with it keep working: revocation
    /// stops new connections, it does not tear down live ones. A host that needs the stronger
    /// property should stop the server.
    public func revokeToken(_ token: String) {
        lock.lock()
        _tokens.removeValue(forKey: token)
        lock.unlock()
    }

    /// Withdraw every token issued under a label.
    public func revokeTokens(label: String) {
        lock.lock()
        for (token, existing) in _tokens where existing == label {
            _tokens.removeValue(forKey: token)
        }
        lock.unlock()
    }

    /// The labels of every live token, for diagnostics. Never the tokens themselves.
    public var tokenLabels: [String] {
        lock.lock(); defer { lock.unlock() }
        return _tokens.values.sorted()
    }

    /// A token good enough to hand a child: 32 bytes of `SecRandomCopyBytes`, hex encoded.
    /// Falls back to `arc4random_buf`, which is also a CSPRNG, if the Security call ever fails.
    public static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            arc4random_buf(&bytes, bytes.count)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// How long a request waits for the main thread before answering `mainThreadUnavailable`
    /// (1005). Set before `start()`.
    public var mainThreadTimeout: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _mainThreadTimeout }
        set { lock.lock(); defer { lock.unlock() }; _mainThreadTimeout = newValue }
    }

    /// Diagnostics go here, prefixed with "ActionUIRemote:". Set before `start()`.
    public var logger: (any ActionUILogger)? {
        get { lock.lock(); defer { lock.unlock() }; return _logger }
        set { lock.lock(); defer { lock.unlock() }; _logger = newValue }
    }

    /// The socket path while running; nil otherwise.
    public var endpoint: String? {
        lock.lock(); defer { lock.unlock() }
        return socketServer?.path
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return socketServer?.isRunning ?? false
    }

    /// Creates a server with the built-in `actionui.*` methods installed. The installation
    /// happens on the main actor: immediately when called on the main thread, otherwise as soon
    /// as the main queue gets to it (before any request can be served, since requests also go
    /// through the main queue).
    public init(host: HostInfo) {
        self.host = host
        onMain { [registry] in
            ActionUIRemoteMethods.install(into: registry, server: self)
        }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Bind the socket and start serving. Throws `UnixSocketServerError`; see it for the path
    /// length limit and the already-started case.
    public func start(socketPath: String) throws {
        // Claim the start under the lock so two concurrent starts cannot both bind; the socket
        // server itself is created and started outside the lock, because it logs through this
        // object's `log`, which reads `logger` under the same (non-recursive) lock.
        lock.lock()
        let claimed = !starting && !(socketServer?.isRunning ?? false)
        if claimed {
            starting = true
        }
        lock.unlock()
        guard claimed else {
            throw UnixSocketServerError.alreadyStarted
        }
        defer {
            lock.lock()
            starting = false
            lock.unlock()
        }
        let server = UnixSocketServer(
            path: socketPath,
            onLine: { [weak self] connectionID, line in
                self?.handle(line: line, connectionID: connectionID)
            },
            onClose: { [weak self] connectionID in
                // Connection ids are handed out sequentially and could in principle be reused;
                // a new connection must never inherit an old one's authentication.
                guard let self else { return }
                self.lock.lock()
                self._authenticated.remove(connectionID)
                self.lock.unlock()
            },
            log: { [weak self] message in
                self?.log(message, .debug)
            }
        )
        try server.start()
        lock.lock()
        let previous = socketServer   // released below, outside the lock: its deinit logs
        socketServer = server
        // Connection ids are per socket server and restart at 1, and a stopped server's
        // connections may never deliver onClose - it holds its server weakly, so once the
        // server deallocates the callback is dropped. Without this, the first connection to a
        // restarted server inherits the authentication of the previous run's first connection.
        _authenticated.removeAll()
        lock.unlock()
        previous?.stop()
        log("serving \(host.name) \(host.version) at \(socketPath)", .info)
    }

    /// Stop serving, close every connection, and unlink the socket file. Idempotent.
    public func stop() {
        lock.lock()
        let server = socketServer
        socketServer = nil
        // Here as well as in start(): a caller may stop and never restart, and leaving the set
        // populated would keep ids alive for a server that no longer exists.
        _authenticated.removeAll()
        lock.unlock()
        server?.stop()
    }

    // MARK: - Extension methods

    /// Register (or replace) a method. Names must be namespaced (`omc.terminate`, `app.quit`);
    /// the `actionui.` prefix is reserved for the built-in table. Safe from any thread: the
    /// registry is updated on the main actor, synchronously when already there.
    public func register(method: String, handler: @escaping Handler) {
        onMain { [registry] in
            registry.handlers[method] = handler
        }
    }

    public func unregister(method: String) {
        onMain { [registry] in
            registry.handlers.removeValue(forKey: method)
        }
    }

    public func setModalResourceResolver(_ resolver: ModalResourceResolver?) {
        onMain { [registry] in
            registry.modalResolver = resolver
        }
    }

    // MARK: - Request processing (connection queue)

    private func handle(line: Data, connectionID: UnixSocketServer.ConnectionID) {
        lock.lock()
        let server = socketServer
        let timeout = _mainThreadTimeout
        lock.unlock()
        guard let server else { return }

        let incoming: JSONRPCIncoming
        do {
            incoming = try JSONRPC.decode(line: line)
        } catch let error as ActionUIRemoteError {
            // Nothing recoverable: answer with a null id.
            server.send(connectionID: connectionID, data: JSONRPC.encodeError(id: nil, error: error))
            return
        } catch {
            let wrapped = ActionUIRemoteError(code: ActionUIRemoteError.internalError, message: "Internal error: \(error)")
            server.send(connectionID: connectionID, data: JSONRPC.encodeError(id: nil, error: wrapped))
            return
        }

        var entries: [Result<JSONRPCRequest, JSONRPCRejection>]
        let isBatch: Bool
        switch incoming {
        case .single(let entry):
            entries = [entry]
            isBatch = false
        case .batch(let batchEntries):
            entries = batchEntries
            isBatch = true
        }

        // Before anything else: an unauthenticated request never reaches the main thread.
        entries = authenticate(entries, connectionID: connectionID)

        let box = RequestBox(entries: entries)
        let needsMainThread = entries.contains { if case .success = $0 { return true } else { return false } }
        var timedOut = false
        if needsMainThread {
            DispatchQueue.main.async { [registry] in
                MainActor.assumeIsolated {
                    registry.execute(box)
                }
                box.semaphore.signal()
            }
            if box.semaphore.wait(timeout: .now() + timeout) == .timedOut {
                box.abandon()
                timedOut = true
                log("main thread did not respond within \(timeout) s; abandoning \(entries.count) request(s) on connection \(connectionID)", .warning)
            }
        }

        let results = timedOut ? [:] : box.takeResults()
        var replies: [Data] = []
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .failure(let rejection):
                if rejection.wantsReply {
                    replies.append(JSONRPC.encodeError(id: rejection.id, error: rejection.error))
                }
            case .success(let request):
                if request.isNotification {
                    continue
                }
                if timedOut {
                    let error = ActionUIRemoteError(
                        code: ActionUIRemoteError.mainThreadUnavailable,
                        message: "The host's main thread did not respond within \(timeout) seconds; the request was not applied unless it was already running")
                    replies.append(JSONRPC.encodeError(id: request.id, error: error))
                    continue
                }
                switch results[index] {
                case .success(let value)?:
                    replies.append(JSONRPC.encodeResult(id: request.id, result: value))
                case .failure(let error)?:
                    replies.append(JSONRPC.encodeError(id: request.id, error: error))
                case nil:
                    replies.append(JSONRPC.encodeError(id: request.id, error: ActionUIRemoteError(
                        code: ActionUIRemoteError.internalError, message: "Internal error: no result was produced")))
                }
            }
        }

        if isBatch {
            if let data = JSONRPC.encodeBatch(replies) {
                server.send(connectionID: connectionID, data: data)
            }
        } else if let data = replies.first {
            server.send(connectionID: connectionID, data: data)
        }
    }

    /// Replace every request this connection may not make with a 1006 rejection.
    ///
    /// Runs on the connection queue, before anything reaches the main thread: an unauthenticated
    /// request must not cost a main-thread hop, or refusing it would itself be a way to stall
    /// the UI.
    ///
    /// A token may arrive two ways, and both are supported deliberately. A long-lived connection
    /// sends it once and is remembered, costing nothing per request afterwards. A client that
    /// opens one connection per request - which PROTOCOL.md section 1 explicitly allows - puts it
    /// on every request instead, so that pattern needs no extra round trip to stay usable.
    ///
    /// The token is stripped before dispatch, so no method handler ever sees it. Host extensions
    /// are third-party code by definition and have no business reading a credential that was not
    /// addressed to them.
    private func authenticate(_ entries: [Result<JSONRPCRequest, JSONRPCRejection>],
                              connectionID: UnixSocketServer.ConnectionID)
        -> [Result<JSONRPCRequest, JSONRPCRejection>] {
        lock.lock()
        let required = _requiresToken
        var authenticated = _authenticated.contains(connectionID)
        lock.unlock()

        func withoutToken(_ request: JSONRPCRequest) -> JSONRPCRequest {
            guard request.params["token"] != nil else { return request }
            var params = request.params
            params.removeValue(forKey: "token")
            return JSONRPCRequest(id: request.id, method: request.method, params: params)
        }

        guard required else {
            // Even with no token required, one must never reach a handler.
            return entries.map { entry in
                guard case .success(let request) = entry else { return entry }
                return .success(withoutToken(request))
            }
        }

        return entries.map { entry in
            guard case .success(let request) = entry else { return entry }

            if !authenticated, let presented = request.params["token"] as? String {
                lock.lock()
                let known = _tokens[presented] != nil
                if known { _authenticated.insert(connectionID) }
                lock.unlock()
                if known {
                    authenticated = true
                    log("connection \(connectionID) authenticated", .debug)
                }
            }

            guard authenticated else {
                let error = ActionUIRemoteError(
                    code: ActionUIRemoteError.unauthenticated,
                    message: "This host requires a token. Pass it as the \"token\" parameter; "
                           + "processes the host spawned receive it in ACTIONUI_REMOTE_TOKEN.")
                return .failure(JSONRPCRejection(id: request.id,
                                                 isNotification: request.isNotification,
                                                 error: error))
            }
            return .success(withoutToken(request))
        }
    }

    // MARK: - Helpers

    /// Run on the main actor: synchronously when already on the main thread (so a host that
    /// registers from its main thread sees the method immediately), otherwise via the main queue.
    private func onMain(_ operation: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                operation()
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    operation()
                }
            }
        }
    }

    func log(_ message: String, _ level: LoggerLevel) {
        logger?.log("ActionUIRemote: \(message)", level)
    }
}

// MARK: - MethodRegistry

/// The method table and the modal resolver, touched only on the main actor.
@MainActor
final class MethodRegistry {
    var handlers: [String: ActionUIRemoteServer.Handler] = [:]
    var modalResolver: ActionUIRemoteServer.ModalResourceResolver?

    nonisolated init() {}

    var methodNames: [String] {
        return handlers.keys.sorted()
    }

    /// Run every valid request in the box, in order, storing a result per index. Stops at the
    /// first request not yet started once the connection has given up waiting: the client was
    /// told nothing after that point was applied.
    func execute(_ box: RequestBox) {
        for (index, entry) in box.entries.enumerated() {
            guard case .success(let request) = entry else { continue }
            if box.isAbandoned {
                return
            }
            let outcome: Result<Any?, ActionUIRemoteError>
            if let handler = handlers[request.method] {
                do {
                    outcome = .success(try handler(request.params))
                } catch let error as ActionUIRemoteError {
                    outcome = .failure(error)
                } catch {
                    outcome = .failure(ActionUIRemoteError(code: ActionUIRemoteError.hostRefused, message: "\(error)"))
                }
            } else {
                outcome = .failure(ActionUIRemoteError(code: ActionUIRemoteError.methodNotFound,
                                                       message: "Method not found: \(request.method)"))
            }
            box.setResult(outcome, at: index)
        }
    }
}

// MARK: - RequestBox

/// Carries one line's requests to the main queue and their results back. The only value that
/// crosses queues; everything inside is behind the lock.
final class RequestBox: @unchecked Sendable {
    let entries: [Result<JSONRPCRequest, JSONRPCRejection>]
    let semaphore = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var results: [Int: Result<Any?, ActionUIRemoteError>] = [:]
    private var abandoned = false

    init(entries: [Result<JSONRPCRequest, JSONRPCRejection>]) {
        self.entries = entries
    }

    func setResult(_ result: Result<Any?, ActionUIRemoteError>, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        results[index] = result
    }

    func takeResults() -> [Int: Result<Any?, ActionUIRemoteError>] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }

    /// The connection gave up waiting. A handler already running completes; the ones not yet
    /// started are skipped (see MethodRegistry.execute), and no result is ever read.
    func abandon() {
        lock.lock()
        defer { lock.unlock() }
        abandoned = true
    }

    var isAbandoned: Bool {
        lock.lock()
        defer { lock.unlock() }
        return abandoned
    }
}

#endif
