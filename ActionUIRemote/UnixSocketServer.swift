// ActionUIRemote/UnixSocketServer.swift
//
// A small Unix domain stream socket server with newline framing, built on BSD sockets and
// DispatchSource. It knows nothing about JSON-RPC or ActionUI: it accepts connections, splits the
// byte stream into lines, hands each line to a callback on the connection's own serial queue, and
// writes back whatever it is given. ActionUIRemoteServer sits on top of it.
//
// Threading: every connection owns a serial queue; all of its state is touched only on that
// queue. The line callback runs on that queue and may block (the remote server blocks in it
// while waiting for the main thread), which is deliberate: no further bytes are read from that
// connection until the callback returns, so requests on one connection are processed strictly
// in order and a slow client cannot pile up work.
//
// Security: the socket file is created 0600, and each accepted connection's peer uid is checked
// with getpeereid(2) against the server's own uid; a mismatch is closed immediately. All file
// descriptors are FD_CLOEXEC so child processes spawned by the host never inherit them.

#if os(macOS)

import Foundation
import Darwin

/// Errors from starting a UnixSocketServer.
public enum UnixSocketServerError: Error, CustomStringConvertible {
    case alreadyStarted
    case pathTooLong(path: String, limit: Int)
    case systemCall(String, errno: Int32)

    public var description: String {
        switch self {
        case .alreadyStarted:
            return "UnixSocketServer is already started"
        case .pathTooLong(let path, let limit):
            return "socket path is \(path.utf8.count) bytes; the limit is \(limit) (sun_path): \(path)"
        case .systemCall(let call, let code):
            return "\(call) failed: \(String(cString: strerror(code))) (errno \(code))"
        }
    }
}

final class UnixSocketServer: @unchecked Sendable {

    typealias ConnectionID = Int

    /// The longest line accepted before the connection is dropped, in bytes. 64 MiB by default.
    let maxLineLength: Int
    let path: String

    private let onLine: @Sendable (ConnectionID, Data) -> Void
    private let onClose: @Sendable (ConnectionID) -> Void
    private let log: @Sendable (String) -> Void

    /// How long a connection whose peer has half-closed may stay open waiting for its outbox to
    /// drain. A peer that has stopped reading cannot be waited on forever - the descriptor is
    /// the scarce thing - and five seconds is far longer than a local socket needs to take a
    /// reply it is waiting for.
    static let lingerAfterPeerClose: TimeInterval = 5

    private let acceptQueue = DispatchQueue(label: "com.abracode.actionui.remote.accept")
    private let lock = NSLock()
    // Guarded by `lock`.
    private var started = false
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [ConnectionID: Connection] = [:]
    private var nextConnectionID: ConnectionID = 1

    /// Maximum usable length of a socket path on this platform (sun_path minus the terminator).
    static var maxPathLength: Int {
        return MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
    }

    /// - Parameters:
    ///   - path: Socket file path. Any existing file there is unlinked on start.
    ///   - maxLineLength: Lines longer than this (without a newline) close the connection.
    ///   - onLine: Called on the connection's queue with each complete line, newline stripped.
    ///   - onClose: Called once when a connection has been closed, for any reason.
    ///   - log: Diagnostic messages.
    init(path: String,
         maxLineLength: Int = 64 * 1024 * 1024,
         onLine: @escaping @Sendable (ConnectionID, Data) -> Void,
         onClose: @escaping @Sendable (ConnectionID) -> Void = { _ in },
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.path = path
        self.maxLineLength = maxLineLength
        self.onLine = onLine
        self.onClose = onClose
        self.log = log
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Create, bind, and start accepting. Throws `UnixSocketServerError` and leaves nothing behind
    /// on failure.
    func start() throws {
        lock.lock()
        do {
            try startLocked()
        } catch {
            lock.unlock()
            throw error
        }
        lock.unlock()
        // Outside the lock: the log callback may take the owner's lock, and the owner may hold
        // its lock while asking this object questions (lock-order discipline: never call out
        // while holding `lock`).
        log("UnixSocketServer listening at \(path)")
    }

    private func startLocked() throws {
        if started {
            throw UnixSocketServerError.alreadyStarted
        }

        let limit = UnixSocketServer.maxPathLength
        guard path.utf8.count <= limit else {
            throw UnixSocketServerError.pathTooLong(path: path, limit: limit)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixSocketServerError.systemCall("socket", errno: errno)
        }

        do {
            try UnixSocketServer.configure(fd: fd)

            // Whatever is at the path is ours by construction (a pid-suffixed name in a private
            // directory); a leftover from a crashed process must not block a new start.
            if unlink(path) != 0 && errno != ENOENT {
                throw UnixSocketServerError.systemCall("unlink", errno: errno)
            }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &address.sun_path) { sunPath in
                sunPath.withMemoryRebound(to: CChar.self, capacity: limit + 1) { buffer in
                    _ = path.withCString { strncpy(buffer, $0, limit + 1) }
                    buffer[limit] = 0
                }
            }
            let bindResult: Int32 = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                throw UnixSocketServerError.systemCall("bind", errno: errno)
            }

            // Private to this user. Not umask: that is process-global and the host has other
            // threads creating files. The parent directory is the primary protection anyway.
            guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
                let code = errno
                unlink(path)
                throw UnixSocketServerError.systemCall("chmod", errno: code)
            }

            guard listen(fd, 16) == 0 else {
                let code = errno
                unlink(path)
                throw UnixSocketServerError.systemCall("listen", errno: code)
            }
        } catch {
            Darwin.close(fd)
            throw error
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPending()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        listenFD = fd
        acceptSource = source
        started = true
        source.resume()
    }

    /// Stop accepting, close every connection, and unlink the socket file. Safe to call more than
    /// once and from any thread.
    func stop() {
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        started = false
        let source = acceptSource
        acceptSource = nil
        listenFD = -1
        // Snapshot only: each connection removes itself (and reports onClose) as it closes.
        let open = Array(connections.values)
        lock.unlock()

        source?.cancel()   // the cancel handler closes the listening fd
        for connection in open {
            connection.queue.async {
                connection.closeOnQueue(reason: "server stopped")
            }
        }
        unlink(path)
        log("UnixSocketServer stopped at \(path)")
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

    /// Queue `data` plus a newline for delivery on the connection. Safe from any thread; when
    /// called on the connection's own queue (from inside `onLine`) the write happens immediately,
    /// which keeps replies in request order.
    func send(connectionID: ConnectionID, data: Data) {
        lock.lock()
        let connection = connections[connectionID]
        lock.unlock()
        guard let connection else {
            log("send: connection \(connectionID) is gone; dropping \(data.count) bytes")
            return
        }
        let framed = data + Data([UInt8(ascii: "\n")])
        if DispatchQueue.getSpecific(key: Connection.queueKey) == connection.id {
            connection.enqueueOnQueue(framed)
        } else {
            connection.queue.async {
                connection.enqueueOnQueue(framed)
            }
        }
    }

    // MARK: - Accepting

    private func acceptPending() {
        while true {
            let fd = accept(listenFDSnapshot(), nil, nil)
            if fd < 0 {
                if errno == EINTR {
                    continue
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                if errno == EBADF {
                    return   // stopped
                }
                log("accept failed: \(String(cString: strerror(errno)))")
                return
            }
            do {
                try UnixSocketServer.configure(fd: fd)
            } catch {
                log("dropping connection: \(error)")
                Darwin.close(fd)
                continue
            }

            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            if getpeereid(fd, &peerUID, &peerGID) != 0 || peerUID != getuid() {
                log("dropping connection from uid \(peerUID): not the server's uid \(getuid())")
                Darwin.close(fd)
                continue
            }

            lock.lock()
            guard started else {
                lock.unlock()
                Darwin.close(fd)
                return
            }
            let id = nextConnectionID
            nextConnectionID += 1
            let connection = Connection(id: id, fd: fd, server: self)
            connections[id] = connection
            lock.unlock()
            connection.startOnQueue()
        }
    }

    private func listenFDSnapshot() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return listenFD
    }

    /// Non-blocking, close-on-exec, and no SIGPIPE on a broken peer.
    private static func configure(fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw UnixSocketServerError.systemCall("fcntl(F_SETFL)", errno: errno)
        }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else {
            throw UnixSocketServerError.systemCall("fcntl(F_SETFD)", errno: errno)
        }
        var one: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw UnixSocketServerError.systemCall("setsockopt(SO_NOSIGPIPE)", errno: errno)
        }
    }

    // MARK: - Connection bookkeeping (called from Connection on its queue)

    fileprivate func connectionDidClose(_ connection: Connection) {
        lock.lock()
        let wasRegistered = connections.removeValue(forKey: connection.id) != nil
        lock.unlock()
        if wasRegistered {
            onClose(connection.id)
        }
    }

    fileprivate func deliver(line: Data, from connection: Connection) {
        onLine(connection.id, line)
    }

    fileprivate func note(_ message: String) {
        log(message)
    }

    // MARK: - Connection

    /// Runs `onLast` when `count` parties have each reported done. Used to close an fd only
    /// after every DispatchSource on it has run its cancel handler.
    fileprivate final class CancellationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private let onLast: () -> Void

        init(count: Int, onLast: @escaping () -> Void) {
            self.remaining = count
            self.onLast = onLast
        }

        func oneDone() {
            lock.lock()
            remaining -= 1
            let last = remaining == 0
            lock.unlock()
            if last {
                onLast()
            }
        }
    }

    fileprivate final class Connection: @unchecked Sendable {
        static let queueKey = DispatchSpecificKey<ConnectionID>()

        let id: ConnectionID
        let fd: Int32
        let queue: DispatchQueue
        private let maxLineLength: Int
        // Weak: the server may be released while a queued close block for this connection is
        // still pending (stop() closes connections asynchronously on their queues).
        private weak var server: UnixSocketServer?

        // All of the following are touched only on `queue`.
        private var readSource: DispatchSourceRead?
        private var writeSource: DispatchSourceWrite?
        private var writeSourceArmed = false
        private var readSourceSuspended = false
        private var inbox = Data()
        private var outbox = Data()
        private var closed = false
        /// The peer has half-closed and this connection is only waiting to finish writing.
        private var peerClosed = false

        init(id: ConnectionID, fd: Int32, server: UnixSocketServer) {
            self.id = id
            self.fd = fd
            self.server = server
            self.maxLineLength = server.maxLineLength
            self.queue = DispatchQueue(label: "com.abracode.actionui.remote.connection.\(id)")
            queue.setSpecific(key: Connection.queueKey, value: id)
        }

        func startOnQueue() {
            queue.async { [self] in
                // stop() may have queued a close ahead of this block; the fd is gone then, and a
                // source created on it would be released while suspended (a libdispatch trap).
                guard !closed else { return }

                // Both sources target this fd; libdispatch requires that the fd stays open until
                // every source on it has run its cancellation, so the last cancel closes it.
                let fd = self.fd
                let pendingCancellations = CancellationCounter(count: 2) {
                    Darwin.close(fd)
                }

                let read = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
                read.setEventHandler { [weak self] in
                    self?.readAvailable()
                }
                read.setCancelHandler {
                    pendingCancellations.oneDone()
                }
                readSource = read

                let write = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
                write.setEventHandler { [weak self] in
                    self?.flushOutbox()
                }
                write.setCancelHandler {
                    pendingCancellations.oneDone()
                }
                writeSource = write
                // A suspended source must not be released while suspended, so the write source
                // is created here and activated only while there is something pending.
                writeSourceArmed = false

                read.resume()
            }
        }

        private func readAvailable() {
            guard !closed else { return }
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = chunk.withUnsafeMutableBytes { buffer -> Int in
                    Darwin.read(fd, buffer.baseAddress, buffer.count)
                }
                if n > 0 {
                    inbox.append(contentsOf: chunk[0..<n])
                    if consumeLines() == false {
                        return   // closed during consumption
                    }
                    continue
                }
                if n == 0 {
                    peerClosedOnQueue()
                    return
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }
                if errno == EINTR {
                    continue
                }
                closeOnQueue(reason: "read failed: \(String(cString: strerror(errno)))")
                return
            }
        }

        /// The peer will not write again. Close, unless a reply it is still waiting for has not
        /// made it out of the outbox yet.
        ///
        /// A half-close is a normal end of a request here, not an abandonment: PROTOCOL.md
        /// section 1 allows a client to open one connection per request, and macOS `nc`
        /// half-closes on stdin EOF by default with no way to ask it not to. Closing on the
        /// zero read would discard whatever `flushOutbox` had left behind after `EAGAIN` - so a
        /// reply small enough for the socket buffer arrived and a large one (`getRows` over a
        /// wide table) silently did not, which is the worst shape a bug like this can take.
        ///
        /// Every line read before this point has already produced its reply: requests are
        /// dispatched synchronously on this queue, so there is nothing else in flight to wait
        /// for and only the bytes already queued matter.
        private func peerClosedOnQueue() {
            peerClosed = true
            if outbox.isEmpty {
                closeOnQueue(reason: "peer closed")
                return
            }

            // The read source is level-triggered and would spin on EOF forever, so it has to be
            // suspended rather than merely ignored.
            if !readSourceSuspended, let source = readSource {
                readSourceSuspended = true
                source.suspend()
            }
            // And a peer that half-closed and then stopped reading must not hold the descriptor
            // for the life of the process. `flushOutbox` closes as soon as it drains; this is
            // only the backstop for the peer that never lets it.
            let linger = UnixSocketServer.lingerAfterPeerClose
            queue.asyncAfter(deadline: .now() + linger) { [weak self] in
                guard let self, !self.closed else { return }
                self.closeOnQueue(reason: "peer closed and did not read the reply within \(linger) s")
            }
        }

        /// Split complete lines out of the inbox and deliver them. Returns false if the
        /// connection was closed (oversized line).
        private func consumeLines() -> Bool {
            while let newline = inbox.firstIndex(of: UInt8(ascii: "\n")) {
                var line = inbox.subdata(in: inbox.startIndex..<newline)
                inbox.removeSubrange(inbox.startIndex...newline)
                if line.last == UInt8(ascii: "\r") {
                    line.removeLast()
                }
                if line.count > maxLineLength {
                    closeOnQueue(reason: "line of \(line.count) bytes exceeds the limit of \(maxLineLength)")
                    return false
                }
                server?.deliver(line: line, from: self)
                if closed {
                    return false
                }
            }
            if inbox.count > maxLineLength {
                closeOnQueue(reason: "unterminated line of \(inbox.count) bytes exceeds the limit of \(maxLineLength)")
                return false
            }
            return true
        }

        func enqueueOnQueue(_ data: Data) {
            guard !closed else { return }
            outbox.append(data)
            flushOutbox()
        }

        private func flushOutbox() {
            guard !closed else { return }
            while !outbox.isEmpty {
                let written = outbox.withUnsafeBytes { buffer -> Int in
                    Darwin.write(fd, buffer.baseAddress, buffer.count)
                }
                if written > 0 {
                    outbox.removeSubrange(outbox.startIndex..<outbox.startIndex.advanced(by: written))
                    continue
                }
                if written == 0 {
                    closeOnQueue(reason: "write returned 0 bytes")
                    return
                }
                if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    // Wait until writable.
                    if !writeSourceArmed, let source = writeSource {
                        writeSourceArmed = true
                        source.resume()
                    }
                    return
                }
                if written < 0 && errno == EINTR {
                    continue
                }
                closeOnQueue(reason: "write failed: \(String(cString: strerror(errno)))")
                return
            }
            if writeSourceArmed, let source = writeSource {
                writeSourceArmed = false
                source.suspend()
            }
            // The outbox is empty. If the peer half-closed while a reply was still queued, this
            // is the moment it has been handed over and the connection has no further use.
            if peerClosed {
                closeOnQueue(reason: "peer closed; reply flushed")
            }
        }

        func closeOnQueue(reason: String) {
            guard !closed else { return }
            closed = true
            server?.note("connection \(id) closed: \(reason)")

            // The fd is closed by the cancellation counter once both sources have canceled.
            // A suspended source cannot be released, so the write source is resumed before cancel.
            if let write = writeSource {
                if !writeSourceArmed {
                    write.resume()
                }
                writeSourceArmed = false
                write.cancel()
                writeSource = nil
            }
            if let read = readSource {
                // Same rule as the write source: a suspended source cannot be released.
                if readSourceSuspended {
                    read.resume()
                }
                readSourceSuspended = false
                read.cancel()
                readSource = nil
            } else {
                // Sources were never created (closed before startOnQueue ran).
                Darwin.close(fd)
            }
            inbox.removeAll()
            outbox.removeAll()
            server?.connectionDidClose(self)
        }
    }
}

#endif
