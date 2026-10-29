// Tests/Application/ActionUIAppFunctionTests.swift
/*
 Tests for the actionUIApp* C functions on Linux, called as a C host calls them, with C function
 pointers as handlers: a window presented before actionUIAppRun opens at the start, its handlers
 fire in order, and closing it ends the run; a run off the main thread, and a setter from another
 thread before the run, are refused and return; a refused nested run leaves other threads able to
 call; a host sets the resource folder (NULL: none); the remote server starts and stops, answers a
 client during the run with the application's name and the window's content size limits, and stops
 when the run ends. The alert and the
 file panels: AppPanelsTests.
*/

import XCTest
import CAdwaita
import Dispatch
import Glibc
@testable import ActionUI
import ActionUIAdwaitaApplication

/// What the C handlers record; C function pointers cannot capture, so they write here.
nonisolated(unsafe) private var events: [String] = []

@MainActor
final class ActionUIAppFunctionTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        events = []
    }

    override func tearDown() async throws {
        for handler in [actionUIAppSetWillFinishLaunchingHandler, actionUIAppSetDidFinishLaunchingHandler, actionUIAppSetWillTerminateHandler] {
            handler(nil)
        }
        actionUIAppSetWindowWillPresentHandler(nil)
        actionUIAppSetWindowWillCloseHandler(nil)
        ActionUIModel.shared.windowModels["c-app-w1"] = nil
        AdwaitaApplication.shared.name = nil
        AdwaitaApplication.shared.applicationID = nil
        AdwaitaTestHost.drainMainLoop()
    }

    func testAHostRunsTheApplicationThroughTheCFunctions() throws {
        actionUIAppSetName("C Host Test")
        actionUIAppSetApplicationID("org.example.CHostTest")
        actionUIAppSetWillFinishLaunchingHandler { events.append("willFinishLaunching") }
        actionUIAppSetWindowWillPresentHandler { uuid in events.append("present \(uuid.map { String(cString: $0) } ?? "")") }
        actionUIAppSetWindowWillCloseHandler { uuid in events.append("close \(uuid.map { String(cString: $0) } ?? "")") }
        actionUIAppSetDidFinishLaunchingHandler {
            events.append("didFinishLaunching")
            actionUIAppCloseWindow("c-app-w1")
            actionUIAppTerminate()
        }
        actionUIAppSetWillTerminateHandler { events.append("willTerminate") }
        actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "From C"}}"#, "c-app-w1", nil)
        actionUIAppRun()
        XCTAssertEqual(events, ["willFinishLaunching", "present c-app-w1", "didFinishLaunching", "close c-app-w1", "willTerminate"])
    }

    func testARunOffTheMainThreadIsRefusedAndReturns() {
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            actionUIAppRun()
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 10), .success, "actionUIAppRun on another thread returns at once")
    }

    func testASetterFromAnotherThreadBeforeTheRunIsRefusedAndReturns() {
        // Waiting for the main thread would never end: it runs no main queue before the run (here
        // it waits on the semaphore).
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            actionUIAppSetName("From a worker")
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 10), .success, "refused, not waiting for the run")
        XCTAssertNotEqual(AdwaitaApplication.shared.name, "From a worker")
    }

    func testARefusedNestedRunLeavesTheRunOpenToOtherThreads() {
        actionUIAppSetDidFinishLaunchingHandler {
            actionUIAppRun()  // refused: the application runs already
            DispatchQueue.global().async {
                actionUIAppSetName("From a worker during the run")
                actionUIAppCloseWindow("c-app-w1")
                actionUIAppTerminate()
            }
        }
        actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "Nested"}}"#, "c-app-w1", nil)
        actionUIAppRun()
        XCTAssertEqual(AdwaitaApplication.shared.name, "From a worker during the run", "the setter waited for the main thread, not refused")
    }

    func testAHostSetsTheResourceFolder() {
        defer { AdwaitaApplication.shared.resourceFolder = nil }
        actionUIAppSetResourceFolder("/opt/example/app")
        XCTAssertEqual(AdwaitaApplication.shared.resourceFolder, "/opt/example/app")
        actionUIAppSetResourceFolder(nil)
        XCTAssertEqual(AdwaitaApplication.shared.resourceFolder, AppBundle.defaultFolder(), "NULL: back to the program's folder")
    }

    /// A socket path of its own in the temporary folder.
    private func remoteSocketPath() -> String {
        "/tmp/aui-app-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
    }

    func testTheRemoteServerStartsAndStops() {
        let path = remoteSocketPath()
        defer { actionUIAppStopRemoteServer() }
        XCTAssertTrue(actionUIAppStartRemoteServer(path))
        XCTAssertEqual(actionUIAppRemoteServerEndpoint().map { String(cString: $0) }, path)
        XCTAssertEqual(getenv("ACTIONUI_REMOTE_ENDPOINT").map { String(cString: $0) }, path, "exported for child processes")
        let token = actionUIAppRemoteServerToken().map { String(cString: $0) }
        XCTAssertEqual(token?.count, 64)
        var copied = [CChar](repeating: 0, count: 128)
        XCTAssertTrue(actionUIAppRemoteCopyServerToken(&copied, copied.count))
        XCTAssertEqual(String(cString: copied), token)
        var tooSmall = [CChar](repeating: 0, count: 16)
        XCTAssertFalse(actionUIAppRemoteCopyServerToken(&tooSmall, tooSmall.count), "a buffer smaller than the token")
        XCTAssertFalse(actionUIAppStartRemoteServer(path), "a second start is refused")

        actionUIAppStopRemoteServer()
        XCTAssertNil(actionUIAppRemoteServerEndpoint())
        XCTAssertNil(actionUIAppRemoteServerToken())
        XCTAssertNil(getenv("ACTIONUI_REMOTE_ENDPOINT"))
        XCTAssertNotEqual(access(path, F_OK), 0, "the socket file is gone")
    }

    func testTheRemoteServerAnswersDuringTheRunAndStopsWhenItEnds() throws {
        let path = remoteSocketPath()
        actionUIAppSetName("Remote Host Test")
        XCTAssertTrue(actionUIAppStartRemoteServer(path))
        let token = try XCTUnwrap(actionUIAppRemoteServerToken().map { String(cString: $0) })
        remoteRequest = (path, #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"token":"\#(token)"}}"#)
        remoteLimitsRequest = #"{"jsonrpc":"2.0","id":2,"method":"actionui.contentSizeLimits","params":{"token":"\#(token)","window":"c-app-w1"}}"#
        actionUIAppSetDidFinishLaunchingHandler {
            // A client on another thread: its request is served on the main thread, which runs
            // the GTK loop, so this proves the loop runs the main queue.
            DispatchQueue.global().async {
                remoteReply = remoteRequest.map { request(path: $0.path, line: $0.line) } ?? nil
                if let path = remoteRequest?.path, let line = remoteLimitsRequest {
                    remoteLimitsReply = request(path: path, line: line)
                }
                actionUIAppCloseWindow("c-app-w1")
                actionUIAppTerminate()
            }
        }
        actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "Remote"}}"#, "c-app-w1", nil)
        actionUIAppRun()
        let reply = remoteReply
        let limitsReply = remoteLimitsReply
        remoteRequest = nil
        remoteReply = nil
        remoteLimitsRequest = nil
        remoteLimitsReply = nil

        let text = try XCTUnwrap(reply, "the client got a reply")
        XCTAssertTrue(text.contains(#""protocolVersion":1"#), text)
        XCTAssertTrue(text.contains(#""name":"Remote Host Test""#), "hello answers with actionUIAppSetName's name: \(text)")
        // The window is on screen, so the GTK renderer measures its Text: bounded both ways.
        let limitsText = try XCTUnwrap(limitsReply, "the client got the limits")
        let limits = try XCTUnwrap((try ActionUIJSON.value(from: limitsText) as? [String: Any])?["result"] as? [String: Any], limitsText)
        XCTAssertEqual(Set(limits.keys), ["minWidth", "minHeight", "maxWidth", "maxHeight"])
        let maxWidth = try XCTUnwrap(JSONNumber.double(limits["maxWidth"]), limitsText)
        XCTAssertGreaterThan(maxWidth, 0, limitsText)
        XCTAssertLessThan(maxWidth, 1000, "a Text's largest width is its text's: \(limitsText)")
        XCTAssertNil(actionUIAppRemoteServerEndpoint(), "the server stopped when the run ended")
        XCTAssertNotEqual(access(path, F_OK), 0, "and its socket file is gone")
    }
}

// MARK: - A remote client

/// The request the run test's client sends, and its reply: the C handler cannot capture.
nonisolated(unsafe) private var remoteRequest: (path: String, line: String)?
nonisolated(unsafe) private var remoteReply: String?
nonisolated(unsafe) private var remoteLimitsRequest: String?
nonisolated(unsafe) private var remoteLimitsReply: String?

/// Sends one line to the Unix socket at `path` and returns the line that comes back (nil after 10
/// seconds, or on any failure).
private func request(path: String, line: String) -> String? {
    let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { sunPath in
        sunPath.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
            _ = path.withCString { strncpy(buffer, $0, capacity - 1) }
        }
    }
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return nil }
    let bytes = Array((line + "\n").utf8)
    guard send(fd, bytes, bytes.count, Int32(MSG_NOSIGNAL)) == bytes.count else { return nil }
    var received: [UInt8] = []
    var byte: UInt8 = 0
    while recv(fd, &byte, 1, 0) == 1 {
        if byte == UInt8(ascii: "\n") {
            return String(decoding: received, as: UTF8.self)
        }
        received.append(byte)
    }
    return nil
}
