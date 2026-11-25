// ActionUIRemote/NamedPipeServer.swift
//
// The remote server's transport on Windows: a local named pipe with newline framing, the Windows
// counterpart of UnixSocketServer.swift, with the same interface (RemoteTransport), so
// ActionUIRemoteServer sits on either. It knows nothing about JSON-RPC or ActionUI: it accepts
// connections, splits each byte stream into lines, hands each line to a callback on the connection's
// own thread, and writes back whatever it is given.
//
// Threading: one thread accepts; each connection has a thread of its own, where all of its state is
// touched and where the line callback runs. The callback may block (the remote server blocks in it
// while waiting for the main thread): nothing more is read from that connection until it returns,
// so requests on one connection run strictly in order, as over a Unix socket. Reads and writes are
// overlapped, so a pending read never holds up a reply.
//
// Security. A named pipe is private only by what is asked of it at creation, so every point is
// explicit here (ActionUIRemote/PROTOCOL.md, "On Windows"):
// - The pipe's security descriptor, given in the call that creates it: the user is its owner and the
//   only account allowed to open it, and its integrity label is the server's own level with no
//   reading or writing up, so a program at a lower level (a sandboxed renderer) cannot open it.
//   Windows' default would let everyone read.
// - PIPE_REJECT_REMOTE_CLIENTS on every instance: without it, other computers reach the pipe as
//   \\host\pipe\name. Not also an access entry denying network sign-ins (NETWORK, S-1-5-2): the
//   user's own processes in an SSH or WinRM session carry that group, and a Unix socket serves them.
// - FILE_FLAG_FIRST_PIPE_INSTANCE: a start fails when the name exists, rather than joining a pipe
//   somebody made first.
// - Each client's own token, read on the connection's thread before its first line is used: the
//   same user as the server, at the server's integrity level or above, not an app container, not a
//   restricted token. The thread acts as the client only between ImpersonateNamedPipeClient and
//   RevertToSelf; if RevertToSelf fails, the process ends, as a thread left acting as another
//   identity must not go on.
// A server in an elevated process (High) therefore serves only elevated clients of the same user.
// A process of the same user at the same level can still read the token out of the host's memory,
// as on every system; the pipe does not claim to stop that.

#if os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import WinSDK

/// The transport ActionUIRemoteServer uses on this system.
typealias RemoteTransport = NamedPipeServer
/// What starting it throws on this system.
public typealias RemoteTransportError = NamedPipeServerError

/// Errors from starting a NamedPipeServer.
public enum NamedPipeServerError: Error, CustomStringConvertible {
    case alreadyStarted
    /// Not a local pipe name: `\\.\pipe\` and then letters, digits, '.', '-' or '_'.
    case invalidName(String)
    /// A pipe of that name exists already (another server's, or one somebody made first); it is not
    /// joined.
    case nameTaken(String)
    case systemCall(String, code: UInt32)

    public var description: String {
        switch self {
        case .alreadyStarted:
            return "NamedPipeServer is already started"
        case .invalidName(let name):
            return "'\(name)' is not a local pipe name (\\\\.\\pipe\\ and then letters, digits, '.', '-' or '_', "
                + "not ending in '.', at most \(NamedPipeServer.maxPathLength) characters)"
        case .nameTaken(let name):
            return "a pipe named \(name) exists already; it is not joined"
        case .systemCall(let call, let code):
            return "\(call) failed: Windows error \(code)"
        }
    }
}

// MARK: - Identity

/// A buffer the caller deallocates, holding what GetTokenInformation tells of `kind`, or nil.
private func tokenInformation(_ token: HANDLE, _ kind: TOKEN_INFORMATION_CLASS) -> UnsafeMutableRawPointer? {
    var size: DWORD = 0
    _ = GetTokenInformation(token, kind, nil, 0, &size)
    guard size > 0 else { return nil }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    guard GetTokenInformation(token, kind, buffer, size, &size) else {
        buffer.deallocate()
        return nil
    }
    return buffer
}

/// The SID's text form (S-1-5-21-...), or nil.
private func sidString(_ sid: PSID?) -> String? {
    var text: LPWSTR? = nil
    guard ConvertSidToStringSidW(sid, &text), let text else { return nil }
    defer { LocalFree(text) }
    return String(decodingCString: text, as: UTF16.self)
}

/// The last subauthority of a mandatory label's SID: the integrity level (0x2000 medium, 0x3000 high).
private func integrityLevel(_ sid: PSID?) -> DWORD? {
    guard let sid, let count = GetSidSubAuthorityCount(sid), count.pointee > 0,
          let level = GetSidSubAuthority(sid, DWORD(count.pointee) - 1) else { return nil }
    return level.pointee
}

/// The account and integrity level of this process, which each client must match. Read once, at a
/// server's start.
private final class ProcessIdentity: @unchecked Sendable {
    /// A copy of the user's SID, owned by this object.
    let userSID: UnsafeMutableRawPointer
    let userSIDText: String
    let integrity: DWORD
    let integritySIDText: String

    private init(userSID: UnsafeMutableRawPointer, userSIDText: String, integrity: DWORD, integritySIDText: String) {
        self.userSID = userSID
        self.userSIDText = userSIDText
        self.integrity = integrity
        self.integritySIDText = integritySIDText
    }

    deinit {
        userSID.deallocate()
    }

    static func current() throws -> ProcessIdentity {
        var token: HANDLE? = nil
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else {
            throw NamedPipeServerError.systemCall("OpenProcessToken", code: GetLastError())
        }
        defer { CloseHandle(token) }
        guard let user = tokenInformation(token, TokenUser) else {
            throw NamedPipeServerError.systemCall("GetTokenInformation(TokenUser)", code: GetLastError())
        }
        defer { user.deallocate() }
        guard let label = tokenInformation(token, TokenIntegrityLevel) else {
            throw NamedPipeServerError.systemCall("GetTokenInformation(TokenIntegrityLevel)", code: GetLastError())
        }
        defer { label.deallocate() }

        let sid = user.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid
        let labelSID = label.assumingMemoryBound(to: TOKEN_MANDATORY_LABEL.self).pointee.Label.Sid
        guard let sid, IsValidSid(sid), let userText = sidString(sid),
              let level = integrityLevel(labelSID), let levelText = sidString(labelSID) else {
            throw NamedPipeServerError.systemCall("reading this process's user and integrity level", code: GetLastError())
        }
        let length = GetLengthSid(sid)
        let copy = UnsafeMutableRawPointer.allocate(byteCount: Int(length), alignment: 16)
        guard CopySid(length, copy, sid) else {
            let code = GetLastError()
            copy.deallocate()
            throw NamedPipeServerError.systemCall("CopySid", code: code)
        }
        return ProcessIdentity(userSID: copy, userSIDText: userText, integrity: level, integritySIDText: levelText)
    }

    /// Why the client at the other end of `pipe` may not use this server, or nil when it may: it must
    /// be this process's user, at this process's integrity level or above, not an app container, and
    /// not a restricted token. Called on the connection's own thread, after the client has written.
    func refusal(ofClientOf pipe: HANDLE) -> String? {
        guard ImpersonateNamedPipeClient(pipe) else {
            return "its identity could not be read (ImpersonateNamedPipeClient: Windows error \(GetLastError()))"
        }
        var clientToken: HANDLE? = nil
        // As this process (OpenAsSelf): a client that allows identification only can still be read.
        let opened = OpenThreadToken(GetCurrentThread(), DWORD(TOKEN_QUERY), true, &clientToken)
        let openError = GetLastError()
        guard RevertToSelf() else {
            fatalError("ActionUIRemote: RevertToSelf failed (Windows error \(GetLastError())); "
                       + "a thread left acting as a pipe client must not go on")
        }
        guard opened, let clientToken else {
            // An anonymous client (ERROR_CANT_OPEN_ANONYMOUS) ends here, as it should.
            return "its token could not be opened (Windows error \(openError))"
        }
        defer { CloseHandle(clientToken) }

        guard let user = tokenInformation(clientToken, TokenUser) else { return "its user could not be read" }
        defer { user.deallocate() }
        guard let sid = user.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, EqualSid(sid, userSID) else {
            return "it runs as another user (\(sidString(user.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid) ?? "unknown"))"
        }

        guard let label = tokenInformation(clientToken, TokenIntegrityLevel) else { return "its integrity level could not be read" }
        defer { label.deallocate() }
        guard let level = integrityLevel(label.assumingMemoryBound(to: TOKEN_MANDATORY_LABEL.self).pointee.Label.Sid) else {
            return "its integrity level could not be read"
        }
        guard level >= integrity else {
            return "its integrity level (0x\(String(level, radix: 16))) is below the server's (0x\(String(integrity, radix: 16)))"
        }

        var isAppContainer: DWORD = 0
        var size: DWORD = 0
        guard GetTokenInformation(clientToken, TokenIsAppContainer, &isAppContainer, DWORD(MemoryLayout<DWORD>.size), &size) else {
            return "whether it is an app container could not be read"
        }
        guard isAppContainer == 0 else { return "it is an app container" }
        guard !IsTokenRestricted(clientToken) else { return "its token is restricted" }
        return nil
    }
}

/// The pipe's security descriptor (owner, access list and integrity label) as SECURITY_ATTRIBUTES,
/// kept for every instance the server makes.
private final class PipeSecurity: @unchecked Sendable {
    private let descriptor: PSECURITY_DESCRIPTOR
    let attributes: UnsafeMutablePointer<SECURITY_ATTRIBUTES>

    init(identity: ProcessIdentity) throws {
        // O: the user owns it (explicit: an elevated process would otherwise make Administrators the
        //    owner). D:P a protected access list: read and write for the user alone; nobody else is
        //    named, so nobody else gets in. S: the mandatory label at this process's own level, no
        //    write up and no read up (NWNR). Other computers are refused by PIPE_REJECT_REMOTE_CLIENTS.
        let user = identity.userSIDText
        let sddl = "O:\(user)D:P(A;;GRGW;;;\(user))S:(ML;;NWNR;;;\(identity.integritySIDText))"
        var made: PSECURITY_DESCRIPTOR? = nil
        let converted = sddl.withCString(encodedAs: UTF16.self) {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &made, nil)
        }
        guard converted, let made else {
            throw NamedPipeServerError.systemCall("ConvertStringSecurityDescriptorToSecurityDescriptorW", code: GetLastError())
        }
        descriptor = made
        attributes = UnsafeMutablePointer<SECURITY_ATTRIBUTES>.allocate(capacity: 1)
        attributes.initialize(to: SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                                      lpSecurityDescriptor: made, bInheritHandle: false))
    }

    deinit {
        attributes.deallocate()
        LocalFree(descriptor)
    }
}

// MARK: - Threads

/// A thread's work, handed through CreateThread's context pointer.
private final class ThreadBody {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
}

/// Starts `body` on a new thread of its own; the thread's handle, or nil when none could be made.
private func startThread(_ body: @escaping () -> Void) -> HANDLE? {
    let context = Unmanaged.passRetained(ThreadBody(body)).toOpaque()
    let thread = CreateThread(nil, 0, { context in
        Unmanaged<ThreadBody>.fromOpaque(context!).takeRetainedValue().body()
        return 0
    }, context, 0, nil)
    if thread == nil {
        Unmanaged<ThreadBody>.fromOpaque(context).release()
    }
    return thread
}

/// An OVERLAPPED in memory that does not move, with a manual-reset event of its own.
private final class Overlapped {
    let pointer: UnsafeMutablePointer<OVERLAPPED>

    init?() {
        guard let event = CreateEventW(nil, true, false, nil) else { return nil }
        pointer = UnsafeMutablePointer<OVERLAPPED>.allocate(capacity: 1)
        pointer.initialize(to: OVERLAPPED())
        pointer.pointee.hEvent = event
    }

    var event: HANDLE { pointer.pointee.hEvent }

    /// Clears what a previous operation left, keeping the event, before the next one starts.
    func reset() {
        let event = pointer.pointee.hEvent
        pointer.pointee = OVERLAPPED()
        pointer.pointee.hEvent = event
    }

    deinit {
        CloseHandle(pointer.pointee.hEvent)
        pointer.deallocate()
    }
}

// MARK: - The server

final class NamedPipeServer: @unchecked Sendable {

    typealias ConnectionID = Int

    /// The longest line accepted before the connection is dropped, in bytes. 64 MiB by default.
    let maxLineLength: Int
    /// The pipe's name, `\\.\pipe\...`.
    let path: String

    /// What one peer may hold of the server before it has proved who it is (as UnixSocketServer's).
    struct Limits: Sendable {
        /// Open connections at once; one more is closed as soon as it is accepted.
        var connections = 64
        /// Seconds a connection may stay open without being trusted (`isTrusted`); 0 for no limit.
        var untrustedLifetime: TimeInterval = 30
        /// Untrusted connections that may hold more than `untrustedLineSize` bytes of a line not yet
        /// complete; one more is closed. A trusted connection may hold up to `maxLineLength`.
        var untrustedLargeLines = 8
        /// The size of an unfinished line above which an untrusted connection counts as large.
        var untrustedLineSize = 64 * 1024
    }

    let limits: Limits
    private let isTrusted: @Sendable (ConnectionID) -> Bool
    private let onLine: @Sendable (ConnectionID, Data) -> Void
    private let onClose: @Sendable (ConnectionID) -> Void
    private let log: @Sendable (String) -> Void

    /// The longest pipe name Windows takes.
    static let maxPathLength = 256
    /// Windows makes at most 255 instances of one pipe; one stays free to wait for the next client.
    static let maxConnections = 254
    /// What every local pipe name begins with.
    static let localPrefix = "\\\\.\\pipe\\"

    private let lock = Lock()
    // Guarded by `lock`.
    private var started = false
    private var acceptLoop: AcceptLoop?
    private var connections: [ConnectionID: Connection] = [:]
    private var nextConnectionID: ConnectionID = 1
    private var largeUntrusted: Set<ConnectionID> = []
    private var loggedConnectionLimit = false

    /// - Parameters:
    ///   - path: The pipe's name, `\\.\pipe\` and then letters, digits, '.', '-' or '_'. `start`
    ///     fails when a pipe of that name exists.
    ///   - maxLineLength: Lines longer than this (without a newline) close the connection.
    ///   - limits: What a peer may hold before it is trusted, and the connection count.
    ///   - isTrusted: Whether a connection has proved who it is; by default every connection has.
    ///   - onLine: Called on the connection's thread with each complete line, newline stripped.
    ///   - onClose: Called once when a connection has been closed, for any reason.
    ///   - log: Diagnostic messages.
    init(path: String,
         maxLineLength: Int = 64 * 1024 * 1024,
         limits: Limits = Limits(),
         isTrusted: @escaping @Sendable (ConnectionID) -> Bool = { _ in true },
         onLine: @escaping @Sendable (ConnectionID, Data) -> Void,
         onClose: @escaping @Sendable (ConnectionID) -> Void = { _ in },
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.path = path
        self.maxLineLength = maxLineLength
        self.limits = limits
        self.isTrusted = isTrusted
        self.onLine = onLine
        self.onClose = onClose
        self.log = log
    }

    deinit {
        stop()
    }

    /// Whether `name` is a local pipe name this server takes: `\\.\pipe\` (any case) and then one
    /// or more letters, digits, '.', '-' or '_', not ending in '.' (Windows drops a final dot, so the
    /// pipe made would not be the name given), at most `maxPathLength` characters in all. Never another
    /// computer's (`\\host\pipe\...`).
    static func isLocalPipeName(_ name: String) -> Bool {
        let characters = Array(name.utf16)
        let prefix = Array(localPrefix.utf16)
        guard characters.count > prefix.count, characters.count <= maxPathLength, characters.last != 0x2E,
              String(decoding: characters[..<prefix.count], as: UTF16.self).lowercased() == localPrefix else {
            return false
        }
        return characters[prefix.count...].allSatisfy { unit in
            (unit >= 0x30 && unit <= 0x39) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)
                || unit == 0x2E || unit == 0x2D || unit == 0x5F
        }
    }

    // MARK: - Lifecycle

    /// Makes the pipe's first instance and starts accepting. Throws `NamedPipeServerError` and
    /// leaves nothing behind on failure.
    func start() throws {
        lock.lock()
        do {
            try startLocked()
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()
        // Outside the lock: the log callback may take the owner's lock (as UnixSocketServer).
        log("NamedPipeServer listening at \(path)")
    }

    private func startLocked() throws {
        if started {
            throw NamedPipeServerError.alreadyStarted
        }
        guard NamedPipeServer.isLocalPipeName(path) else {
            throw NamedPipeServerError.invalidName(path)
        }
        let identity = try ProcessIdentity.current()
        let security = try PipeSecurity(identity: identity)
        let instances = DWORD(min(max(limits.connections, 1), NamedPipeServer.maxConnections) + 1)
        let loop = try AcceptLoop(name: path, security: security, identity: identity, maxInstances: instances, server: self)
        guard loop.begin() else {
            throw NamedPipeServerError.systemCall("CreateThread", code: GetLastError())
        }
        acceptLoop = loop
        started = true
    }

    /// Stops accepting and closes every connection. The pipe's name goes once the last connection's
    /// thread has closed its instance, a moment later. Safe to call more than once and from any
    /// thread; it waits for the accepting thread only.
    func stop() {
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        started = false
        let loop = acceptLoop
        acceptLoop = nil
        let open = Array(connections.values)
        lock.unlock()

        loop?.end()
        for connection in open {
            connection.requestClose(reason: "server stopped")
        }
        log("NamedPipeServer stopped at \(path)")
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    var connectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return connections.count
    }

    // MARK: - Sending

    /// Queues `data` plus a newline for delivery on the connection. Safe from any thread; from inside
    /// `onLine` the reply goes out when the callback returns, in request order.
    func send(connectionID: ConnectionID, data: Data) {
        lock.lock()
        let connection = connections[connectionID]
        lock.unlock()
        guard let connection else {
            log("send: connection \(connectionID) is gone; dropping \(data.count) bytes")
            return
        }
        connection.enqueue(data + Data([UInt8(ascii: "\n")]))
    }

    // MARK: - Accepting (called by the accept loop on its thread)

    /// Takes a connected pipe instance: registers it and starts its thread, or closes it when the
    /// server has stopped or is at its connection limit.
    fileprivate func admit(_ pipe: HANDLE, identity: ProcessIdentity) {
        lock.lock()
        guard started else {
            lock.unlock()
            CloseHandle(pipe)
            return
        }
        guard connections.count < limits.connections else {
            let first = !loggedConnectionLimit
            loggedConnectionLimit = true
            lock.unlock()
            CloseHandle(pipe)
            if first {
                log("refusing connections: \(limits.connections) are open, the limit")
            }
            return
        }
        let id = nextConnectionID
        nextConnectionID += 1
        guard let connection = Connection(id: id, pipe: pipe, server: self, identity: identity) else {
            let code = GetLastError()
            lock.unlock()
            CloseHandle(pipe)
            log("dropping connection: its events could not be made (Windows error \(code))")
            return
        }
        connections[id] = connection
        lock.unlock()
        if !connection.begin() {
            connection.closeUnstarted(reason: "its thread could not be started (Windows error \(GetLastError()))")
        }
    }

    fileprivate func note(_ message: String) {
        log(message)
    }

    // MARK: - Connection bookkeeping (called from Connection on its thread)

    fileprivate func connectionDidClose(_ connection: Connection) {
        lock.lock()
        let wasRegistered = connections.removeValue(forKey: connection.id) != nil
        largeUntrusted.remove(connection.id)
        if connections.count < limits.connections {
            loggedConnectionLimit = false
        }
        lock.unlock()
        if wasRegistered {
            onClose(connection.id)
        }
    }

    fileprivate func deliver(line: Data, from connection: Connection) {
        onLine(connection.id, line)
    }

    fileprivate func connectionIsTrusted(_ id: ConnectionID) -> Bool {
        isTrusted(id)
    }

    /// Whether the connection may go on holding a large unfinished line while untrusted: true when it
    /// already counts, or a place among `limits.untrustedLargeLines` is free.
    fileprivate func admitLargeUntrusted(_ id: ConnectionID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if largeUntrusted.contains(id) { return true }
        guard largeUntrusted.count < limits.untrustedLargeLines else { return false }
        largeUntrusted.insert(id)
        return true
    }

    fileprivate func releaseLargeUntrusted(_ id: ConnectionID) {
        lock.lock()
        largeUntrusted.remove(id)
        lock.unlock()
    }

    // MARK: - The accept loop

    /// Waits for clients on one pipe instance at a time, on a thread of its own. Holds the server
    /// weakly, so a server let go stops (deinit) as a UnixSocketServer does.
    fileprivate final class AcceptLoop: @unchecked Sendable {
        private let name: String
        private let security: PipeSecurity
        private let identity: ProcessIdentity
        private let maxInstances: DWORD
        private weak var server: NamedPipeServer?
        private let stopEvent: HANDLE
        private var thread: HANDLE?
        /// The instance waiting for a client: made by the start (the first, which fails when the name
        /// exists), then by the loop's thread alone.
        private var listening: HANDLE?

        init(name: String, security: PipeSecurity, identity: ProcessIdentity, maxInstances: DWORD,
             server: NamedPipeServer) throws {
            self.name = name
            self.security = security
            self.identity = identity
            self.maxInstances = maxInstances
            self.server = server
            guard let event = CreateEventW(nil, true, false, nil) else {
                throw NamedPipeServerError.systemCall("CreateEventW", code: GetLastError())
            }
            stopEvent = event
            let (first, code) = makeInstance(first: true)
            guard let first else {
                CloseHandle(event)
                // ERROR_ACCESS_DENIED or ERROR_PIPE_BUSY: the name is someone's already.
                if code == DWORD(ERROR_ACCESS_DENIED) || code == DWORD(ERROR_PIPE_BUSY) {
                    throw NamedPipeServerError.nameTaken(name)
                }
                throw NamedPipeServerError.systemCall("CreateNamedPipeW", code: code)
            }
            listening = first
        }

        deinit {
            if let listening {
                CloseHandle(listening)
            }
            CloseHandle(stopEvent)
        }

        /// A new instance of the pipe, with the server's security and flags, or nil and the error.
        private func makeInstance(first: Bool) -> (HANDLE?, DWORD) {
            var openMode = DWORD(PIPE_ACCESS_DUPLEX) | DWORD(FILE_FLAG_OVERLAPPED)
            if first {
                openMode |= DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE)
            }
            let pipeMode = DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_READMODE_BYTE) | DWORD(PIPE_WAIT)
                | DWORD(PIPE_REJECT_REMOTE_CLIENTS)
            let handle = name.withCString(encodedAs: UTF16.self) {
                CreateNamedPipeW($0, openMode, pipeMode, maxInstances, 64 * 1024, 64 * 1024, 0, security.attributes)
            }
            guard let handle, handle != INVALID_HANDLE_VALUE else {
                return (nil, GetLastError())
            }
            return (handle, 0)
        }

        /// Starts the loop's thread; false when it could not be made.
        func begin() -> Bool {
            thread = startThread { [self] in run() }
            return thread != nil
        }

        /// Stops the loop and waits for its thread, which closes the waiting instance.
        func end() {
            SetEvent(stopEvent)
            if let thread {
                if GetThreadId(thread) != GetCurrentThreadId() {
                    WaitForSingleObject(thread, INFINITE)
                }
                CloseHandle(thread)
                self.thread = nil
            }
        }

        private func stopRequested(waitingMilliseconds: DWORD = 0) -> Bool {
            WaitForSingleObject(stopEvent, waitingMilliseconds) == WAIT_OBJECT_0
        }

        private func run() {
            guard let overlapped = Overlapped() else {
                server?.note("NamedPipeServer cannot accept: no event (Windows error \(GetLastError()))")
                return
            }
            while !stopRequested() {
                guard let instance = listening else {
                    let (made, code) = makeInstance(first: false)
                    if let made {
                        listening = made
                    } else {
                        server?.note("CreateNamedPipeW failed: Windows error \(code); trying again")
                        if stopRequested(waitingMilliseconds: 100) { break }
                    }
                    continue
                }
                overlapped.reset()
                var connected = false
                if ConnectNamedPipe(instance, overlapped.pointer) {
                    // An overlapped ConnectNamedPipe answers through GetLastError; a true is unexpected.
                    server?.note("ConnectNamedPipe returned at once; the instance is replaced")
                } else {
                    let code = GetLastError()
                    if code == DWORD(ERROR_PIPE_CONNECTED) {
                        connected = true
                    } else if code == DWORD(ERROR_IO_PENDING) {
                        var events: [HANDLE?] = [stopEvent, overlapped.event]
                        let waited = WaitForMultipleObjects(DWORD(events.count), &events, false, INFINITE)
                        var transferred: DWORD = 0
                        if waited != WAIT_OBJECT_0 + 1 {
                            // Stopping, or the wait failed: the pending connect must finish before its
                            // OVERLAPPED goes. A failed wait stops the loop too; it would only fail again.
                            if waited != WAIT_OBJECT_0 {
                                server?.note("NamedPipeServer stops accepting: waiting failed (Windows error \(GetLastError()))")
                            }
                            CancelIoEx(instance, overlapped.pointer)
                            _ = GetOverlappedResult(instance, overlapped.pointer, &transferred, true)
                            break
                        }
                        connected = GetOverlappedResult(instance, overlapped.pointer, &transferred, true)
                        if !connected {
                            server?.note("a client's connection failed: Windows error \(GetLastError())")
                        }
                    } else {
                        server?.note("ConnectNamedPipe failed: Windows error \(code)")
                    }
                }
                listening = nil
                if connected {
                    // The next instance first, so a client finds one waiting as soon as possible.
                    let (made, _) = makeInstance(first: false)
                    listening = made
                    if let server {
                        server.admit(instance, identity: identity)
                    } else {
                        CloseHandle(instance)
                        break
                    }
                } else {
                    CloseHandle(instance)
                }
            }
            if let listening {
                CloseHandle(listening)
                self.listening = nil
            }
        }
    }

    // MARK: - Connection

    fileprivate final class Connection: @unchecked Sendable {
        let id: ConnectionID
        private let pipe: HANDLE
        // Weak: the server may be let go while this connection's thread still closes it.
        private weak var server: NamedPipeServer?
        private let identity: ProcessIdentity
        private let maxLineLength: Int
        private let limits: Limits
        private var thread: HANDLE?

        /// Set to end the connection from another thread (`requestClose`).
        private let closeEvent: HANDLE
        /// Set when replies are queued.
        private let wakeEvent: HANDLE
        private let lock = Lock()
        // Guarded by `lock`.
        private var outgoing = Data()
        private var closeReason: String?

        // Touched only on the connection's thread.
        private let readOverlapped: Overlapped
        private let writeOverlapped: Overlapped
        private static let readSize = 64 * 1024
        private let readBuffer: UnsafeMutableRawPointer
        private var writeBuffer: UnsafeMutableRawPointer?
        private var writeCount = 0
        private var readPending = false
        private var writePending = false
        private var identified = false
        private var closed = false
        private var inbox = Data()
        /// How much of `inbox` has been searched for a newline already, so each byte is scanned once.
        private var scanned = 0
        /// Whether this connection holds one of the server's places for a large untrusted line.
        private var holdsLargePlace = false

        init?(id: ConnectionID, pipe: HANDLE, server: NamedPipeServer, identity: ProcessIdentity) {
            guard let closeEvent = CreateEventW(nil, true, false, nil) else { return nil }
            guard let wakeEvent = CreateEventW(nil, false, false, nil) else {
                CloseHandle(closeEvent)
                return nil
            }
            guard let readOverlapped = Overlapped(), let writeOverlapped = Overlapped() else {
                CloseHandle(closeEvent)
                CloseHandle(wakeEvent)
                return nil
            }
            self.id = id
            self.pipe = pipe
            self.server = server
            self.identity = identity
            self.maxLineLength = server.maxLineLength
            self.limits = server.limits
            self.closeEvent = closeEvent
            self.wakeEvent = wakeEvent
            self.readOverlapped = readOverlapped
            self.writeOverlapped = writeOverlapped
            // Last: a failed init runs no deinit, so nothing that needs freeing comes before.
            self.readBuffer = UnsafeMutableRawPointer.allocate(byteCount: Connection.readSize, alignment: 16)
        }

        deinit {
            CloseHandle(closeEvent)
            CloseHandle(wakeEvent)
            readBuffer.deallocate()
            writeBuffer?.deallocate()
        }

        /// Starts the connection's thread; false when it could not be made.
        func begin() -> Bool {
            let thread = startThread { [self] in run() }
            guard let thread else { return false }
            CloseHandle(thread)   // nothing waits for it
            return true
        }

        /// Closes a connection whose thread never started, on the caller's thread.
        func closeUnstarted(reason: String) {
            close(reason: reason)
        }

        /// Ends the connection from any thread; its own thread closes it.
        func requestClose(reason: String) {
            lock.lock()
            if closeReason == nil {
                closeReason = reason
            }
            lock.unlock()
            SetEvent(closeEvent)
        }

        /// Queues bytes to write; safe from any thread.
        func enqueue(_ data: Data) {
            lock.lock()
            outgoing.append(data)
            lock.unlock()
            SetEvent(wakeEvent)
        }

        private func run() {
            let opened = GetTickCount64()
            // A peer that never proves who it is does not keep the instance. Checked once, when the
            // lifetime ends, as UnixSocketServer does: a connection trusted by then stays open even if
            // its token is revoked later (it is refused from its next request instead). Clamped: a
            // finite but huge lifetime (the setters refuse only infinity and NaN) would trap in the
            // conversion; 1e9 s is over 30 years.
            let lifetime = limits.untrustedLifetime
            let allowed = lifetime > 0 ? UInt64(min(lifetime, 1e9) * 1000) : 0
            var lifetimeChecked = !(lifetime > 0)
            while !closed {
                if !readPending {
                    startRead()
                    if closed { return }
                }
                // A finished write first: the wait below answers the read before it, so a client that
                // keeps sending would otherwise hold replies back.
                if writePending, WaitForSingleObject(writeOverlapped.event, 0) == WAIT_OBJECT_0 {
                    finishWrite()
                    if closed { return }
                }
                if !writePending {
                    startWrite()
                    if closed { return }
                }

                var events: [HANDLE?] = [closeEvent, readOverlapped.event, wakeEvent]
                if writePending {
                    events.append(writeOverlapped.event)
                }
                // Here at every turn, not only on the wait's timeout: a peer that keeps a read
                // completing at every turn would never let the wait time out.
                var timeout = INFINITE
                if !lifetimeChecked {
                    let elapsed = GetTickCount64() - opened
                    if elapsed >= allowed {
                        lifetimeChecked = true
                        if !(server?.connectionIsTrusted(id) ?? true) {
                            close(reason: "not authenticated within \(lifetime) s")
                            continue
                        }
                    } else {
                        timeout = DWORD(min(allowed - elapsed, UInt64(INFINITE - 1)))
                    }
                }
                let waited = WaitForMultipleObjects(DWORD(events.count), &events, false, timeout)
                switch waited {
                case WAIT_OBJECT_0:
                    lock.lock()
                    let reason = closeReason ?? "closed"
                    lock.unlock()
                    close(reason: reason)
                case WAIT_OBJECT_0 + 1:
                    finishRead()
                case WAIT_OBJECT_0 + 2:
                    break   // replies queued: the next turn writes them
                case WAIT_OBJECT_0 + 3:
                    finishWrite()
                case DWORD(WAIT_TIMEOUT):
                    break   // the lifetime has ended: the next turn checks the peer
                default:
                    close(reason: "waiting failed: Windows error \(GetLastError())")
                }
            }
        }

        private func startRead() {
            readOverlapped.reset()
            if ReadFile(pipe, readBuffer, DWORD(Connection.readSize), nil, readOverlapped.pointer) {
                readPending = true   // finished already; its event is set, and finishRead takes it
                return
            }
            let code = GetLastError()
            if code == DWORD(ERROR_IO_PENDING) {
                readPending = true
            } else {
                close(reason: code == DWORD(ERROR_BROKEN_PIPE) ? "peer closed" : "read failed: Windows error \(code)")
            }
        }

        private func finishRead() {
            var count: DWORD = 0
            let ok = GetOverlappedResult(pipe, readOverlapped.pointer, &count, false)
            let code = GetLastError()
            readPending = false
            guard ok else {
                close(reason: code == DWORD(ERROR_BROKEN_PIPE) ? "peer closed" : "read failed: Windows error \(code)")
                return
            }
            guard count > 0 else { return }
            if !identified {
                // Before anything the client sent is used: who is it?
                if let refusal = identity.refusal(ofClientOf: pipe) {
                    close(reason: "refused: \(refusal)")
                    return
                }
                identified = true
            }
            inbox.append(readBuffer.assumingMemoryBound(to: UInt8.self), count: Int(count))
            _ = consumeLines()
        }

        private func startWrite() {
            lock.lock()
            let data = outgoing
            outgoing = Data()
            lock.unlock()
            guard !data.isEmpty else { return }
            writeBuffer?.deallocate()
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 16)
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
            writeBuffer = buffer
            writeCount = data.count
            writeOverlapped.reset()
            if WriteFile(pipe, buffer, DWORD(data.count), nil, writeOverlapped.pointer) {
                writePending = true
                return
            }
            let code = GetLastError()
            if code == DWORD(ERROR_IO_PENDING) {
                writePending = true
            } else {
                close(reason: code == DWORD(ERROR_NO_DATA) || code == DWORD(ERROR_BROKEN_PIPE)
                      ? "peer closed" : "write failed: Windows error \(code)")
            }
        }

        private func finishWrite() {
            var count: DWORD = 0
            let ok = GetOverlappedResult(pipe, writeOverlapped.pointer, &count, false)
            let code = GetLastError()
            writePending = false
            guard ok else {
                close(reason: code == DWORD(ERROR_NO_DATA) || code == DWORD(ERROR_BROKEN_PIPE)
                      ? "peer closed" : "write failed: Windows error \(code)")
                return
            }
            if Int(count) < writeCount, let buffer = writeBuffer {
                // The rest goes ahead of anything queued since.
                let rest = Data(bytes: buffer.advanced(by: Int(count)), count: writeCount - Int(count))
                lock.lock()
                outgoing = rest + outgoing
                lock.unlock()
            }
            writeBuffer?.deallocate()
            writeBuffer = nil
            writeCount = 0
        }

        /// Splits complete lines out of the inbox and delivers them. Returns false if the connection
        /// was closed (an oversized line). The same rules as UnixSocketServer's.
        private func consumeLines() -> Bool {
            while let newline = inbox[(inbox.startIndex + scanned)...].firstIndex(of: UInt8(ascii: "\n")) {
                var line = inbox.subdata(in: inbox.startIndex..<newline)
                inbox.removeSubrange(inbox.startIndex...newline)
                scanned = 0
                if line.last == UInt8(ascii: "\r") {
                    line.removeLast()
                }
                if line.count > maxLineLength {
                    close(reason: "line of \(line.count) bytes exceeds the limit of \(maxLineLength)")
                    return false
                }
                server?.deliver(line: line, from: self)
                if closed {
                    return false
                }
            }
            scanned = inbox.count
            if inbox.count > maxLineLength {
                close(reason: "unterminated line of \(inbox.count) bytes exceeds the limit of \(maxLineLength)")
                return false
            }
            // An untrusted peer may hold a large unfinished line only while few others do: the token
            // rides on the first request, so the line cap itself cannot be lowered.
            if inbox.count > limits.untrustedLineSize {
                if !holdsLargePlace, let server, !server.connectionIsTrusted(id) {
                    guard server.admitLargeUntrusted(id) else {
                        close(reason: "too many unauthenticated connections hold a large unfinished line")
                        return false
                    }
                    holdsLargePlace = true
                }
            } else if holdsLargePlace {
                holdsLargePlace = false
                server?.releaseLargeUntrusted(id)
            }
            return true
        }

        /// Ends the connection: the pending reads and writes are canceled and finished (their
        /// OVERLAPPED and buffers must outlive them), then the instance is closed.
        private func close(reason: String) {
            guard !closed else { return }
            closed = true
            server?.note("connection \(id) closed: \(reason)")
            if readPending || writePending {
                CancelIoEx(pipe, nil)
                var count: DWORD = 0
                if readPending {
                    _ = GetOverlappedResult(pipe, readOverlapped.pointer, &count, true)
                    readPending = false
                }
                if writePending {
                    _ = GetOverlappedResult(pipe, writeOverlapped.pointer, &count, true)
                    writePending = false
                }
            }
            CloseHandle(pipe)
            inbox.removeAll()
            scanned = 0
            if holdsLargePlace {
                holdsLargePlace = false
                server?.releaseLargeUntrusted(id)
            }
            lock.lock()
            outgoing.removeAll()
            lock.unlock()
            server?.connectionDidClose(self)
        }
    }
}

#endif
