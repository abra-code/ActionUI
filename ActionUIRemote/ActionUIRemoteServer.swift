// ActionUIRemote/ActionUIRemoteServer.swift
//
// The remote binding's server: a Unix domain socket speaking newline-delimited JSON-RPC 2.0,
// executing every request on the main actor against ActionUIModel.shared, with a registry that
// hosts extend with their own namespaced methods (OMC registers `omc.*`).
//
// Threading model (see PROTOCOL.md):
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

#if os(macOS) || os(Linux)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch
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

    /// A method implementation. Receives the request's named params, already JSON-decoded into
    /// Swift-native values: Bool, Int (a number that fits one without loss), Double, String,
    /// arrays, string-keyed dictionaries, and ActionUIJSONNull for null. Returns a JSON-ready
    /// result of the same kinds (`nil` encodes as null; Foundation values are converted). Throw
    /// `ActionUIRemoteError` to answer with a specific code; any other error is reported as
    /// `hostRefused` (1004) with its description as the message.
    public typealias Handler = @MainActor (_ params: [String: Any]) throws -> Any?

    /// Resolves the `path` form of `actionui.presentModal` (a resource name or a relative path)
    /// to a file URL. Without a resolver only absolute paths are accepted.
    public typealias ModalResourceResolver = @MainActor (_ nameOrPath: String) -> URL?

    /// One request as the host's method policy sees it: the method, its named params (the token
    /// removed), and the label of the token the connection presented (nil when the host requires
    /// none).
    public struct RemoteCall {
        public let method: String
        public let params: [String: Any]
        public let tokenLabel: String?

        /// For a host that tests its own policy.
        public init(method: String, params: [String: Any] = [:], tokenLabel: String? = nil) {
            self.method = method
            self.params = params
            self.tokenLabel = tokenLabel
        }
    }

    /// Whether to run a request: true runs it, false answers it with 1004 (host refused). Called
    /// on the main actor before every request, built-in or the host's own, so it must return
    /// promptly.
    public typealias MethodPolicy = @MainActor (_ call: RemoteCall) -> Bool

    /// The built-in methods the `valuesOnly` preset allows: reading the windows and their
    /// elements, and reading and setting values, states, rows and selection of elements that
    /// exist. Nothing that inserts, removes or presents, no property changes, no performAction.
    /// Setting a value or state can still fire the element's value-change action, as a change
    /// the user made would.
    public static let valuesOnlyMethods: Set<String> = [
        "actionui.hello", "actionui.listWindows", "actionui.getElementInfo", "actionui.contentSizeLimits",
        "actionui.getValue", "actionui.setValue", "actionui.getValueString", "actionui.setValueString",
        "actionui.getProperty",
        "actionui.getState", "actionui.getStateString", "actionui.setState", "actionui.setStateString",
        "actionui.getColumnCount", "actionui.getRows", "actionui.setRows", "actionui.appendRows",
        "actionui.appendText", "actionui.clearRows",
        "actionui.selectRow", "actionui.selectRowWithContent", "actionui.clearSelection",
    ]

    /// A policy that allows `valuesOnlyMethods` and refuses everything else, host methods
    /// included: a host that also offers its own combines it, `{ valuesOnly($0) || $0.method == "app.save" }`.
    public static let valuesOnly: MethodPolicy = { call in valuesOnlyMethods.contains(call.method) }

    /// Bumped only for changes that break existing clients (a result shape, a removed method).
    public static let protocolVersion = 1

    public let host: HostInfo

    private let lock = Lock()
    // Guarded by `lock`.
    private var _mainThreadTimeout: TimeInterval = 10
    private var _logger: (any ActionUILogger)?
    private var socketServer: UnixSocketServer?
    private var starting = false
    /// token -> label. Many are live at once: a host mints one per unit of work it spawns, so a
    /// grant can be withdrawn when that work ends without disturbing anything else.
    private var _tokens: [String: String] = [:]
    /// token -> scope, for the tokens minted with one (guarded by `lock`, removed with the token).
    private var _scopes: [String: TokenScope] = [:]
    private var _requiresToken = false
    /// Connections that have already presented a valid token, with that token. A client may send
    /// it once and then stop, or send it on every request; both work. Revoking the token ends the
    /// connection's authentication.
    private var _authenticated: [UnixSocketServer.ConnectionID: String] = [:]

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

    // MARK: - Limits

    /// Open connections at once (64 by default); one more is closed as soon as it is accepted.
    /// Read at `start`.
    public var connectionLimit: Int {
        get { lock.lock(); defer { lock.unlock() }; return _limits.connections }
        set { lock.lock(); _limits.connections = max(1, newValue); lock.unlock() }
    }

    /// Seconds a connection may stay open without presenting a valid token, when one is required
    /// (30 by default; 0 for no limit). Read at `start`.
    public var authenticationTimeout: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _limits.untrustedLifetime }
        // Infinity and NaN count as no limit, as 0 does.
        set { lock.lock(); _limits.untrustedLifetime = newValue.isFinite ? max(0, newValue) : 0; lock.unlock() }
    }

    /// Connections that may hold more than 64 KiB of an unfinished line before presenting a
    /// valid token, when one is required (8 by default); one more is closed. The token rides on a
    /// connection's first request, which may be large, so the line cap itself stays. Read at
    /// `start`.
    public var unauthenticatedLargeLineLimit: Int {
        get { lock.lock(); defer { lock.unlock() }; return _limits.untrustedLargeLines }
        set { lock.lock(); _limits.untrustedLargeLines = max(0, newValue); lock.unlock() }
    }

    // Guarded by `lock`.
    private var _limits = UnixSocketServer.Limits()

    /// Whether a connection counts as trusted for the socket server's limits: always when no
    /// token is required, else once it has presented a valid one.
    private func isTrusted(_ connectionID: UnixSocketServer.ConnectionID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_requiresToken || _authenticated[connectionID] != nil
    }

    /// What one token may reach, within what the host's method policy allows: the windows it may
    /// address (nil: all), and whether only the `valuesOnly` methods. A request naming another
    /// window answers 1001 (unknown window), and `hello` and `listWindows` list only these windows;
    /// a method outside the preset answers 1004. A scope applies only while the server requires a
    /// token, and a child given a scoped token must not also inherit the start-up one
    /// (`ACTIONUI_REMOTE_TOKEN`), or it can present that instead.
    public struct TokenScope: Sendable, Equatable {
        public var windows: Set<String>?
        public var valuesOnly: Bool

        public init(windows: Set<String>? = nil, valuesOnly: Bool = false) {
            self.windows = windows
            self.valuesOnly = valuesOnly
        }
    }

    /// Mint nothing, register what the caller minted. The host owns token generation because it
    /// owns the lifetime: it knows when the work a token was issued for has finished.
    ///
    /// `label` is free-form and is what `revokeTokens(label:)` matches on - a command id, say, so
    /// a host can withdraw one command's grant without touching another's. `scope` limits what
    /// the token reaches (nil: everything the method policy allows).
    public func addToken(_ token: String, label: String, scope: TokenScope? = nil) {
        guard !token.isEmpty else { return }
        lock.lock()
        _tokens[token] = label
        _scopes[token] = scope
        lock.unlock()
    }

    /// Withdraw one token. A connection authenticated with it is no longer: its next request is
    /// refused unless it presents a token that is still live. A request already accepted runs to
    /// its end.
    public func revokeToken(_ token: String) {
        lock.lock()
        _tokens.removeValue(forKey: token)
        _scopes.removeValue(forKey: token)
        _authenticated = _authenticated.filter { $0.value != token }
        lock.unlock()
    }

    /// Withdraw every token issued under a label, and the authentication of the connections that
    /// presented one of them, as revokeToken does.
    public func revokeTokens(label: String) {
        lock.lock()
        let revoked = Set(_tokens.filter { $0.value == label }.keys)
        for token in revoked {
            _tokens.removeValue(forKey: token)
            _scopes.removeValue(forKey: token)
        }
        _authenticated = _authenticated.filter { !revoked.contains($0.value) }
        lock.unlock()
    }

    /// The labels of every live token, for diagnostics. Never the tokens themselves.
    public var tokenLabels: [String] {
        lock.lock(); defer { lock.unlock() }
        return _tokens.values.sorted()
    }

    /// A token good enough to hand a child: 32 random bytes, hex encoded (64 characters).
    /// `SystemRandomNumberGenerator` is the system's cryptographically secure generator:
    /// arc4random_buf on Apple platforms, getrandom on Linux.
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let digits = Array("0123456789abcdef")
        var token = ""
        token.reserveCapacity(64)
        for _ in 0..<32 {
            let byte = UInt8.random(in: .min ... .max, using: &generator)
            token.append(digits[Int(byte >> 4)])
            token.append(digits[Int(byte & 0x0f)])
        }
        return token
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
        lock.lock()
        let limits = _limits
        lock.unlock()
        let server = UnixSocketServer(
            path: socketPath,
            limits: limits,
            isTrusted: { [weak self] connectionID in
                self?.isTrusted(connectionID) ?? true
            },
            onLine: { [weak self] connectionID, line in
                self?.handle(line: line, connectionID: connectionID)
            },
            onClose: { [weak self] connectionID in
                // Connection ids are handed out sequentially and could in principle be reused;
                // a new connection must never inherit an old one's authentication.
                guard let self else { return }
                self.lock.lock()
                self._authenticated.removeValue(forKey: connectionID)
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

    /// Register (or replace) a host method. The name must be namespaced, with something on both
    /// sides of the first dot (`omc.terminate`, `app.quit`), and not in the `actionui.` namespace,
    /// which holds the built-in methods: such a name is refused (false, logged), as the C
    /// function does. A host that means to replace a built-in calls `replaceBuiltIn(method:)`.
    /// Safe from any thread: the registry is updated on the main actor, synchronously when already
    /// there.
    @discardableResult
    public func register(method: String, handler: @escaping Handler) -> Bool {
        guard Self.isHostMethodName(method) else {
            log("not registering '\(method)': a host method is namespaced (app.name) and outside actionui.", .warning)
            return false
        }
        onMain { [registry] in
            registry.handlers[method] = handler
        }
        return true
    }

    /// Register the host's own handler under a name in the `actionui.` namespace, for a host that
    /// must change what a built-in does: it replaces the built-in of that name. The name is not
    /// checked against the built-ins, so a name no built-in has adds a method there, which a later
    /// version's built-in of that name would not replace. False (logged) for a name outside the
    /// namespace. Safe from any thread, with the timing of `register(method:)`.
    @discardableResult
    public func replaceBuiltIn(method: String, handler: @escaping Handler) -> Bool {
        guard Self.isBuiltInMethodName(method) else {
            log("not replacing '\(method)': not a name in the actionui. namespace", .warning)
            return false
        }
        onMain { [registry] in
            registry.handlers[method] = handler
        }
        return true
    }

    /// Remove a built-in method (a name in the `actionui.` namespace), so peers cannot call it:
    /// `actionui.insertElement` for a host whose peers should only read and set values, say.
    /// False (logged) for any other name. Safe from any thread, with the timing of
    /// `register(method:)`.
    @discardableResult
    public func removeBuiltIn(method: String) -> Bool {
        guard Self.isBuiltInMethodName(method) else {
            log("not removing '\(method)': not a name in the actionui. namespace", .warning)
            return false
        }
        onMain { [registry] in
            registry.handlers.removeValue(forKey: method)
        }
        return true
    }

    /// Whether `name` is a host method's: namespaced, with something on both sides of the first
    /// dot, and not in the reserved `actionui.` namespace.
    static func isHostMethodName(_ name: String) -> Bool {
        guard let dot = name.firstIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else {
            return false
        }
        return name[name.startIndex..<dot] != "actionui"
    }

    /// Whether `name` is in the `actionui.` namespace, with something after the dot.
    static func isBuiltInMethodName(_ name: String) -> Bool {
        name.hasPrefix("actionui.") && name.count > "actionui.".count
    }

    /// Add `actionui.performAction` (PROTOCOL.md section 7), which fires an element's configured
    /// action as if the user had activated it, with the element, part and context a click would
    /// carry. Off by default, for test harnesses. Leaving it off does not keep a token holder from
    /// the host's action handlers: `presentModal` with an `onDismissActionID` then `dismissModal`,
    /// or an element with `onAppearActionID`, reach any action id too (PROTOCOL.md section 7). It
    /// ends with the server, like any registration. Safe from any thread, with the timing of
    /// `register(method:)`.
    public func enablePerformAction() {
        onMain { [registry] in
            registry.handlers["actionui.performAction"] = ActionUIRemoteMethods.performAction
        }
    }

    /// Remove a host method registered with `register(method:)`. A built-in's name is refused
    /// (false, logged); `removeBuiltIn(method:)` removes one on purpose.
    @discardableResult
    public func unregister(method: String) -> Bool {
        guard Self.isHostMethodName(method) else {
            log("not unregistering '\(method)': built-in methods are removed with removeBuiltIn(method:)", .warning)
            return false
        }
        onMain { [registry] in
            registry.handlers.removeValue(forKey: method)
        }
        return true
    }

    /// Install the host's method policy, asked before every request (nil: every request runs, as
    /// before). It ends with the server, like any registration. Safe from any thread, with the
    /// timing of `register(method:)`.
    public func setMethodPolicy(_ policy: MethodPolicy?) {
        onMain { [registry] in
            registry.policy = policy
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
        let tokenLabel: String?
        let scope: TokenScope?
        (entries, tokenLabel, scope) = authenticate(entries, connectionID: connectionID)

        let box = RequestBox(entries: entries, tokenLabel: tokenLabel, scope: scope)
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

    /// Replace every request this connection may not make with a 1006 rejection, and return the
    /// label of the token the connection authenticated with (nil when no token is required), read
    /// under the same lock as the check so a revocation in between cannot hand the method policy a
    /// nil label for a request that was let through.
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
        -> (entries: [Result<JSONRPCRequest, JSONRPCRejection>], tokenLabel: String?, scope: TokenScope?) {
        lock.lock()
        let required = _requiresToken
        var label = _authenticated[connectionID].flatMap { _tokens[$0] }
        var scope = _authenticated[connectionID].flatMap { _scopes[$0] }
        var authenticated = label != nil
        lock.unlock()

        func withoutToken(_ request: JSONRPCRequest) -> JSONRPCRequest {
            guard request.params["token"] != nil else { return request }
            var params = request.params
            params.removeValue(forKey: "token")
            return JSONRPCRequest(id: request.id, method: request.method, params: params)
        }

        guard required else {
            // Even with no token required, one must never reach a handler.
            return (entries.map { entry in
                guard case .success(let request) = entry else { return entry }
                return .success(withoutToken(request))
            }, nil, nil)
        }

        let checked: [Result<JSONRPCRequest, JSONRPCRejection>] = entries.map { entry in
            guard case .success(let request) = entry else { return entry }

            if !authenticated, let presented = request.params["token"] as? String {
                lock.lock()
                let presentedLabel = _tokens[presented]
                let presentedScope = _scopes[presented]
                if presentedLabel != nil { _authenticated[connectionID] = presented }
                lock.unlock()
                if presentedLabel != nil {
                    label = presentedLabel
                    scope = presentedScope
                    authenticated = true
                    log("connection \(connectionID) authenticated", .debug)
                }
            }

            guard authenticated else {
                let error = ActionUIRemoteError(
                    code: ActionUIRemoteError.unauthenticated,
                    message: "This host requires a token. Pass it as the \"token\" parameter; "
                           + "processes the host spawned receive it in ACTIONUI_REMOTE_TOKEN, or "
                           + "on the descriptor named by ACTIONUI_REMOTE_TOKEN_FD.")
                return .failure(JSONRPCRejection(id: request.id,
                                                 isNotification: request.isNotification,
                                                 error: error))
            }
            return .success(withoutToken(request))
        }
        return (checked, label, scope)
    }

    // MARK: - Helpers

    /// Run on the main actor: synchronously when already on the main thread (so a host that
    /// registers from its main thread sees the method immediately), otherwise via the main queue.
    private func onMain(_ operation: @escaping @MainActor @Sendable () -> Void) {
        if isMainThread {
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
    var policy: ActionUIRemoteServer.MethodPolicy?

    nonisolated init() {}

    var methodNames: [String] {
        return handlers.keys.sorted()
    }

    /// `result` with the window lists of `hello` and `listWindows` narrowed to `windows`, a token's
    /// scope; anything else as it is. A list of another shape (a host's replacement of either
    /// method) is withheld rather than passed on unfiltered.
    static func withinScope(_ result: Any?, method: String, windows: Set<String>?) -> Any? {
        guard let windows else { return result }
        switch method {
        case "actionui.listWindows":
            return (result as? [String])?.filter { windows.contains($0) } ?? [String]()
        case "actionui.hello":
            guard var hello = result as? [String: Any] else { return result }
            if let listed = hello["windows"] as? [String] {
                hello["windows"] = listed.filter { windows.contains($0) }
            } else {
                hello.removeValue(forKey: "windows")
            }
            return hello
        default:
            return result
        }
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
            let windows = box.scope?.windows
            if let scope = box.scope, scope.valuesOnly,
               !ActionUIRemoteServer.valuesOnlyMethods.contains(request.method) {
                outcome = .failure(ActionUIRemoteError(code: ActionUIRemoteError.hostRefused,
                                                       message: "Refused by the host: \(request.method) is outside this token's scope"))
            } else if let windows, let window = request.params["window"] as? String, !windows.contains(window) {
                // As for a window that does not exist: the token is not told that it does.
                outcome = .failure(ActionUIRemoteError(code: ActionUIRemoteError.unknownWindow,
                                                       message: "Unknown window: \(window)"))
            } else if let policy, !policy(ActionUIRemoteServer.RemoteCall(method: request.method, params: request.params,
                                                                           tokenLabel: box.tokenLabel)) {
                outcome = .failure(ActionUIRemoteError(code: ActionUIRemoteError.hostRefused,
                                                       message: "Refused by the host: \(request.method)"))
            } else if let handler = handlers[request.method] {
                do {
                    outcome = .success(Self.withinScope(try handler(request.params), method: request.method,
                                                        windows: windows))
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
    /// The label of the token the connection presented, for the method policy.
    let tokenLabel: String?
    /// That token's scope, if it was minted with one.
    let scope: ActionUIRemoteServer.TokenScope?
    let semaphore = DispatchSemaphore(value: 0)

    private let lock = Lock()
    private var results: [Int: Result<Any?, ActionUIRemoteError>] = [:]
    private var abandoned = false

    init(entries: [Result<JSONRPCRequest, JSONRPCRejection>], tokenLabel: String? = nil,
         scope: ActionUIRemoteServer.TokenScope? = nil) {
        self.entries = entries
        self.tokenLabel = tokenLabel
        self.scope = scope
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
