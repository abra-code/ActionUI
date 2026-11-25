// ActionUIRemote/ActionUIRemoteSharedServer+Windows.swift
//
// The process-wide server on Windows: ActionUIRemoteSharedServer.swift's entry points, over a named
// pipe. Two differences from macOS and Linux:
// - Nothing goes into the environment. On macOS and Linux startShared exports the endpoint and the
//   token so every process the host starts inherits them; on Windows many more processes would
//   (WebView2's browser, GPU and renderer processes, a program Windows starts for a link), so a host
//   hands them to the child it means instead: actionUIRemoteServerEndpoint, and a token of the
//   child's own from actionUIRemoteMintToken (ActionUIRemote/PROTOCOL.md, "On Windows").
// - No socket file: the pipe goes when its last handle closes, so there is nothing to remove at exit.

#if os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import WinSDK
import ActionUI

/// Process-wide state. A final class with its own lock rather than globals, so Swift 6 sees one
/// Sendable box instead of mutable global state.
private final class SharedServerStorage: @unchecked Sendable {
    let lock = Lock()
    var server: ActionUIRemoteServer?        // guarded by lock
    var starting = false                     // guarded by lock
    /// The token minted for the host at start (label "host"), nil when none is required.
    var startupToken: String?                // guarded by lock
    /// The limits the next shared server starts with (`sharedLimits`).
    var limits = RemoteTransport.Limits()    // guarded by lock
}

private let sharedStorage = SharedServerStorage()

public extension ActionUIRemoteServer {

    // MARK: - Host identity

    /// How the running process names itself when the host has nothing better: the process name and
    /// "0" (the application layer passes the application's name).
    static func currentProcessHost() -> HostInfo {
        return HostInfo(name: ProcessInfo.processInfo.processName, version: "0")
    }

    // MARK: - The process-wide server

    /// The pipe name `startShared` uses when the caller does not choose one, new for each call:
    /// `\\.\pipe\actionui-<process id>-<32 random hex digits>`. Pipe names are one list for the whole
    /// computer that anyone can read, so the random part is no secret; it is there so nobody can make
    /// the name first.
    static func defaultSocketPath() -> String {
        let random = String(ActionUIRemoteServer.makeToken().prefix(32))
        return "\(NamedPipeServer.localPrefix)actionui-\(GetCurrentProcessId())-\(random)"
    }

    /// The process-wide server, or nil when none is running. This is where a host registers its own
    /// methods: `ActionUIRemoteServer.shared?.register(method: "omc.terminate") { ... }`.
    static var shared: ActionUIRemoteServer? {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        return sharedStorage.server
    }

    /// The pipe name the shared server is serving, or nil when none is running.
    static var sharedEndpoint: String? {
        return shared?.endpoint
    }

    /// The token `startShared` minted for the host (label "host"), or nil when the server requires
    /// none or none is running. Not in the environment on Windows.
    static var sharedStartupToken: String? {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        return sharedStorage.startupToken
    }

    /// The limits the next `startShared` gives its server, as on macOS and Linux.
    static func setSharedLimits(connections: Int, authenticationTimeout: TimeInterval,
                                unauthenticatedLargeLines: Int) {
        sharedStorage.lock.lock()
        sharedStorage.limits.connections = max(1, connections)
        sharedStorage.limits.untrustedLifetime = authenticationTimeout.isFinite ? max(0, authenticationTimeout) : 0
        sharedStorage.limits.untrustedLargeLines = max(0, unauthenticatedLargeLines)
        sharedStorage.lock.unlock()
    }

    /// The limits the next `startShared` uses: (connections, authentication timeout, large lines).
    static var sharedLimits: (connections: Int, authenticationTimeout: TimeInterval, unauthenticatedLargeLines: Int) {
        sharedStorage.lock.lock()
        defer { sharedStorage.lock.unlock() }
        let limits = sharedStorage.limits
        return (limits.connections, limits.untrustedLifetime, limits.untrustedLargeLines)
    }

    /// Start the process-wide server. Unlike macOS and Linux, nothing is exported into the
    /// environment (see the top of this file).
    ///
    /// - Parameters:
    ///   - socketPath: the pipe's name, `\\.\pipe\...`; `nil` takes `defaultSocketPath()`. A pipe of
    ///     that name that exists already makes the start throw `NamedPipeServerError.nameTaken`.
    ///   - host: how to answer `actionui.hello`. Defaults to the running process.
    ///   - logger: where the server's diagnostics go. Nil is silent.
    ///   - requireToken: mint a token for the host and refuse connections without a valid one.
    /// - Returns: the pipe's name.
    /// - Throws: `NamedPipeServerError.alreadyStarted` when a shared server is already running, and
    ///   whatever `start(socketPath:)` throws.
    ///
    /// Safe to call from any thread, and it calls out to the logger only outside its own lock.
    @discardableResult
    static func startShared(socketPath: String? = nil,
                            host: HostInfo = currentProcessHost(),
                            logger: (any ActionUILogger)? = nil,
                            requireToken: Bool = true) throws -> String {
        // Claim the start under the lock, then build and start outside it (start logs, and a
        // logger may ask this type a question), as on macOS and Linux.
        sharedStorage.lock.lock()
        let claimed = !sharedStorage.starting && sharedStorage.server == nil
        if claimed {
            sharedStorage.starting = true
        }
        sharedStorage.lock.unlock()
        guard claimed else {
            throw NamedPipeServerError.alreadyStarted
        }
        let path = socketPath ?? defaultSocketPath()

        let server = ActionUIRemoteServer(host: host)
        server.logger = logger
        sharedStorage.lock.lock()
        let limits = sharedStorage.limits
        sharedStorage.lock.unlock()
        server.connectionLimit = limits.connections
        server.authenticationTimeout = limits.untrustedLifetime
        server.unauthenticatedLargeLineLimit = limits.untrustedLargeLines
        let token = requireToken ? ActionUIRemoteServer.makeToken() : nil
        if let token {
            server.addToken(token, label: "host")
            server.requiresToken = true
        }
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
        sharedStorage.startupToken = token
        sharedStorage.starting = false
        sharedStorage.lock.unlock()
        return path
    }

    /// Stop the process-wide server and close its connections. Does nothing when none is running.
    /// Safe to call from any thread.
    static func stopShared() {
        sharedStorage.lock.lock()
        let server = sharedStorage.server
        sharedStorage.server = nil
        sharedStorage.startupToken = nil
        sharedStorage.lock.unlock()
        server?.stop()                          // outside the lock: stop logs
    }
}

/// The environment names of PROTOCOL.md section 9, named once so that hosts and tests agree. On
/// Windows the server sets none of them (see the top of this file): a host sets them for a child it
/// starts.
public enum ActionUIRemoteEnvironment {
    /// The pipe name of the host's server.
    public static let endpoint = "ACTIONUI_REMOTE_ENDPOINT"
    /// The window a child process was started for, when there is one.
    public static let windowUUID = "ACTIONUI_WINDOW_UUID"
    /// The token a child sends without being asked.
    public static let token = "ACTIONUI_REMOTE_TOKEN"
}

#endif
