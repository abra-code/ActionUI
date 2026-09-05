// ActionUIRemoteTests/UnixSocketServerTests.swift
//
// Exercises the socket layer through real BSD sockets from the test process: framing, ordering,
// concurrent connections, the line-length limit, stale socket files, path limits, and stop().
// The server never needs the main thread, so the client here may block on it.

#if os(macOS)

import XCTest
import Darwin
@testable import ActionUIRemote

private typealias RawClient = TestSocketClient

final class UnixSocketServerTests: XCTestCase {

    private var socketPath: String!
    private var server: UnixSocketServer?

    override func setUp() {
        super.setUp()
        socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("aui-test-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock").path
    }

    override func tearDown() {
        server?.stop()
        server = nil
        unlink(socketPath)
        super.tearDown()
    }

    /// An echo server: every line comes straight back.
    private func startEchoServer(maxLineLength: Int = 64 * 1024 * 1024,
                                 onClose: @escaping @Sendable (Int) -> Void = { _ in }) throws -> UnixSocketServer {
        let box = ServerBox()
        let echo = UnixSocketServer(path: socketPath, maxLineLength: maxLineLength, onLine: { id, line in
            box.server?.send(connectionID: id, data: line)
        }, onClose: onClose)
        box.server = echo
        try echo.start()
        server = echo
        return echo
    }

    private final class ServerBox: @unchecked Sendable {
        var server: UnixSocketServer?
    }

    func testEchoOneLine() throws {
        _ = try startEchoServer()
        let client = try RawClient(path: socketPath)
        client.write("{\"hello\":1}\n")
        XCTAssertEqual(client.readLine(), "{\"hello\":1}")
    }

    func testLineSplitAcrossWritesAndCRLFStripped() throws {
        _ = try startEchoServer()
        let client = try RawClient(path: socketPath)
        client.write("first ha")
        usleep(50_000)
        client.write("lf\r\n")
        XCTAssertEqual(client.readLine(), "first half")
    }

    func testTwoLinesInOneWriteArriveInOrder() throws {
        _ = try startEchoServer()
        let client = try RawClient(path: socketPath)
        client.write("one\ntwo\n")
        XCTAssertEqual(client.readLine(), "one")
        XCTAssertEqual(client.readLine(), "two")
    }

    func testEmptyLineIsDeliveredAsEmpty() throws {
        _ = try startEchoServer()
        let client = try RawClient(path: socketPath)
        client.write("\n")
        XCTAssertEqual(client.readLine(), "")
    }

    func testTwoConcurrentConnectionsAreIndependent() throws {
        let echo = try startEchoServer()
        let a = try RawClient(path: socketPath)
        let b = try RawClient(path: socketPath)
        a.write("from a\n")
        b.write("from b\n")
        XCTAssertEqual(b.readLine(), "from b")
        XCTAssertEqual(a.readLine(), "from a")
        // Give the accept loop a moment to register both before counting.
        let deadline = Date().addingTimeInterval(2)
        while echo.connectionCount < 2 && Date() < deadline { usleep(10_000) }
        XCTAssertEqual(echo.connectionCount, 2)
    }

    func testLargeLineRoundTrips() throws {
        _ = try startEchoServer()
        let client = try RawClient(path: socketPath)
        let payload = String(repeating: "x", count: 300_000)
        // Write and read on different threads: the server's echo may fill the socket buffer
        // before the client finishes writing, which would deadlock a single-threaded client.
        let reader = DispatchQueue(label: "reader")
        let expectation = expectation(description: "echoed")
        let received = ServerBoxString()
        reader.async {
            received.value = client.readLine()
            expectation.fulfill()
        }
        client.write(payload + "\n")
        wait(for: [expectation], timeout: 10)
        XCTAssertEqual(received.value?.count, payload.count)
    }

    private final class ServerBoxString: @unchecked Sendable {
        var value: String?
    }

    func testOversizedLineClosesTheConnection() throws {
        let closed = expectation(description: "connection closed")
        _ = try startEchoServer(maxLineLength: 32, onClose: { _ in closed.fulfill() })
        let client = try RawClient(path: socketPath)
        client.write(String(repeating: "y", count: 33) + "\n")
        XCTAssertTrue(client.waitForEOF(), "the server must close a connection that sends an oversized line")
        wait(for: [closed], timeout: 5)
    }

    func testOversizedUnterminatedLineClosesTheConnection() throws {
        let closed = expectation(description: "connection closed")
        _ = try startEchoServer(maxLineLength: 32, onClose: { _ in closed.fulfill() })
        let client = try RawClient(path: socketPath)
        client.write(String(repeating: "z", count: 40))   // no newline at all
        XCTAssertTrue(client.waitForEOF())
        wait(for: [closed], timeout: 5)
    }

    func testPeerCloseIsReported() throws {
        let closed = expectation(description: "connection closed")
        let echo = try startEchoServer(onClose: { _ in closed.fulfill() })
        do {
            let client = try RawClient(path: socketPath)
            client.write("ping\n")
            XCTAssertEqual(client.readLine(), "ping")
        }   // client deinit closes the socket
        wait(for: [closed], timeout: 5)
        let deadline = Date().addingTimeInterval(2)
        while echo.connectionCount > 0 && Date() < deadline { usleep(10_000) }
        XCTAssertEqual(echo.connectionCount, 0)
    }

    // MARK: - A peer that half-closes

    // PROTOCOL.md section 1: a client may shut its write side down as soon as it has sent, which
    // is what macOS `nc` does when its stdin ends and what it gives no way to avoid. EOF from the
    // peer therefore ends the requests, not the connection.

    func testAHalfClosedPeerStillGetsItsReply() throws {
        let closed = expectation(description: "connection closed")
        _ = try startEchoServer(onClose: { _ in closed.fulfill() })
        let client = try RawClient(path: socketPath)
        client.write("ping\n")
        client.halfClose()
        XCTAssertEqual(client.readLine(), "ping")
        // And it is not held open afterwards: a reply that fitted the socket buffer left nothing
        // to wait for, so the close is immediate rather than at the end of the linger window.
        XCTAssertTrue(client.waitForEOF(), "the server must close once the last reply is out")
        wait(for: [closed], timeout: 5)
    }

    func testAHalfClosedPeerGetsAReplyTooLargeForTheSocketBuffer() throws {
        _ = try startEchoServer()
        let client = try RawClient(path: socketPath)

        // Far larger than any socket buffer this connection will get, so the echo cannot be
        // handed over in one write: `flushOutbox` is guaranteed to stop on EAGAIN with the tail
        // still queued. That leftover is the only thing closing on the zero read destroyed, and
        // it is why the bug was invisible - a short reply arrived and a long one did not.
        let payload = String(repeating: "x", count: 256 * 1024)
        client.write(payload + "\n")
        client.halfClose()

        let reply = client.readLine()
        XCTAssertEqual(reply?.count, payload.count, "the reply was truncated at the close")
        XCTAssertEqual(reply, payload)
        XCTAssertTrue(client.waitForEOF(), "the server must close once the last reply is out")
    }

    func testAHalfClosedPeerThatNeverReadsIsNotWaitedOnForever() throws {
        // The other half of the contract: deferring the close must not become a way to pin a
        // descriptor. A peer that half-closes and then reads nothing is let go after the linger
        // window, whatever it left unread.
        let closed = expectation(description: "connection closed")
        let echo = try startEchoServer(onClose: { _ in closed.fulfill() })
        let client = try RawClient(path: socketPath, timeoutSeconds: 30)
        client.write(String(repeating: "y", count: 256 * 1024) + "\n")
        client.halfClose()

        wait(for: [closed], timeout: UnixSocketServer.lingerAfterPeerClose + 10)
        let deadline = Date().addingTimeInterval(2)
        while echo.connectionCount > 0 && Date() < deadline { usleep(10_000) }
        XCTAssertEqual(echo.connectionCount, 0, "the connection must not outlive the linger window")
    }

    func testStaleSocketFileIsReplaced() throws {
        // A leftover regular file at the path (a crashed server would leave a socket; a regular
        // file is the harder case) must not prevent starting.
        FileManager.default.createFile(atPath: socketPath, contents: Data("stale".utf8))
        _ = try startEchoServer()
        var info = stat()
        XCTAssertEqual(stat(socketPath, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK, "the path must now be a socket")
        XCTAssertEqual(info.st_mode & 0o777, 0o600, "the socket file must be private to the user")
        let client = try RawClient(path: socketPath)
        client.write("alive\n")
        XCTAssertEqual(client.readLine(), "alive")
    }

    func testPathTooLongThrowsWithoutLeavingAFile() {
        let longPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(repeating: "p", count: 120) + ".sock").path
        let s = UnixSocketServer(path: longPath, onLine: { _, _ in })
        XCTAssertThrowsError(try s.start()) { error in
            guard case UnixSocketServerError.pathTooLong(_, let limit) = error else {
                return XCTFail("expected pathTooLong, got \(error)")
            }
            XCTAssertEqual(limit, UnixSocketServer.maxPathLength)
            XCTAssertEqual(limit, 103)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: longPath))
        XCTAssertFalse(s.isRunning)
    }

    func testStartTwiceThrowsAndStopUnlinksAndIsIdempotent() throws {
        let echo = try startEchoServer()
        XCTAssertTrue(echo.isRunning)
        XCTAssertThrowsError(try echo.start()) { error in
            guard case UnixSocketServerError.alreadyStarted = error else {
                return XCTFail("expected alreadyStarted, got \(error)")
            }
        }
        echo.stop()
        XCTAssertFalse(echo.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertThrowsError(try RawClient(path: socketPath), "nothing must be listening after stop()")
        echo.stop()   // second stop is a no-op
        // And the same instance can be started again.
        try echo.start()
        let client = try RawClient(path: socketPath)
        client.write("again\n")
        XCTAssertEqual(client.readLine(), "again")
    }

    func testStopClosesOpenConnections() throws {
        let closed = expectation(description: "connection closed")
        let echo = try startEchoServer(onClose: { _ in closed.fulfill() })
        let client = try RawClient(path: socketPath)
        client.write("x\n")
        XCTAssertEqual(client.readLine(), "x")
        echo.stop()
        XCTAssertTrue(client.waitForEOF())
        wait(for: [closed], timeout: 5)
    }

    func testListeningDescriptorIsCloseOnExec() throws {
        // Child processes spawned by the host must not inherit the socket. Verify through the
        // flag on a fresh connection's fd from the server side is not observable here, so check
        // the behavior end to end: a child that inherits nothing sees no open Unix sockets.
        _ = try startEchoServer()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "/usr/sbin/lsof -p $$ -a -U 2>/dev/null | /usr/bin/grep -c '\(socketPath!)' || true"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(output, "0", "a child process must not inherit the listening socket")
    }
}

#endif
