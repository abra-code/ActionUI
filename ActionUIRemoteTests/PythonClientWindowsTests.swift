// ActionUIRemoteTests/PythonClientWindowsTests.swift
//
// The Python client's checks on Windows (actionui_remote_windows.py), against the real server over a
// named pipe: the token from the environment is sent and a wrong one refused; another computer's
// endpoint is refused before anything is opened; and a pipe that is not this user's gets no token
// (one owned by the Administrators group, which only an elevated process can make: skipped when this
// one is not elevated). The rest of the client runs in PythonClientIntegrationTests.

#if os(Windows)

import XCTest
import WinSDK
@testable import ActionUI
@testable import ActionUIRemote

/// A child that never finished: a failure, not a skip (a stalled open of another computer's pipe would
/// look like this).
private struct PythonTimedOut: Error, CustomStringConvertible {
    let output: String
    var description: String { "the Python child did not finish within 60 s:\n\(output)" }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// This process's user SID as text (S-1-5-21-...), or nil.
private func currentUserSIDText() -> String? {
    var token: HANDLE? = nil
    guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { return nil }
    defer { CloseHandle(token) }
    var size: DWORD = 0
    _ = GetTokenInformation(token, TokenUser, nil, 0, &size)
    guard size > 0 else { return nil }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { buffer.deallocate() }
    guard GetTokenInformation(token, TokenUser, buffer, size, &size) else { return nil }
    var text: LPWSTR? = nil
    guard ConvertSidToStringSidW(buffer.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, &text), let text else {
        return nil
    }
    defer { LocalFree(text) }
    return String(decodingCString: text, as: UTF16.self)
}

@MainActor
final class PythonClientWindowsTests: XCTestCase {

    private var endpoint: String!
    private var windowUUID: String!
    private var server: ActionUIRemoteServer!

    override func setUp() async throws {
        ActionUIModel.resetForRemoteTests()
        ActionUIModel.shared.logger = QuietLogger(maxLevel: .warning)
        windowUUID = UUID().uuidString
        _ = try ActionUIModel.shared.loadDescription(
            from: ["id": 10, "type": "VStack", "children": [["id": 2, "type": "TextField", "properties": ["title": "Name"]]]],
            windowUUID: windowUUID)
        endpoint = makeTestEndpoint("aui-pywin")
        server = ActionUIRemoteServer(host: .init(name: "PythonWindowsHost", version: "0.1"))
        server.logger = QuietLogger(maxLevel: .warning)
        try server.start(socketPath: endpoint)
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        ActionUIModel.resetForRemoteTests()
    }

    private static var pythonFolder: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // ActionUIRemoteTests
            .deletingLastPathComponent()        // package root
            .appendingPathComponent("ActionUIRemote/Python")
            .path
    }

    /// Runs `source` with `python -c` in ActionUIRemote/Python, the endpoint and window in the
    /// environment, plus `extra`. The exit status and the merged output.
    private func runPython(_ source: String, extra: [String: String?] = [:]) throws -> (status: Int32, output: String) {
        let fileManager = FileManager.default
        guard let python = pythonCandidates().first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("Python is not available on this machine")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", source]
        process.currentDirectoryURL = URL(fileURLWithPath: Self.pythonFolder)
        var environment = ProcessInfo.processInfo.environment
        environment["ACTIONUI_REMOTE_ENDPOINT"] = endpoint
        environment["ACTIONUI_WINDOW_UUID"] = windowUUID
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment.removeValue(forKey: "ACTIONUI_REMOTE_TOKEN")
        for (key, value) in extra {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = OutputBox()
        let drained = expectation(description: "the child's output reached EOF")
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                drained.fulfill()
            } else {
                output.append(chunk)
            }
        }
        let exited = expectation(description: "the child exited")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        guard XCTWaiter().wait(for: [exited, drained], timeout: 60) == .completed else {
            process.terminate()
            pipe.fileHandleForReading.readabilityHandler = nil
            throw PythonTimedOut(output: output.text)
        }
        return (process.terminationStatus, output.text)
    }

    func testTheTokenInTheEnvironmentIsSentAndAWrongOneRefused() throws {
        let token = ActionUIRemoteServer.makeToken()
        server.addToken(token, label: "child")
        server.requiresToken = true

        let source = """
        import os, actionui_remote as aui
        win = aui.Window(os.environ["ACTIONUI_WINDOW_UUID"])
        win.set_string(2, "over the pipe")
        print("ok", win.get_string(2))
        """
        let run = try runPython(source, extra: ["ACTIONUI_REMOTE_TOKEN": token])
        XCTAssertEqual(run.status, 0, run.output)
        XCTAssertTrue(run.output.contains("ok over the pipe"), run.output)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2) as? String, "over the pipe")

        let refused = """
        import os, actionui_remote as aui
        try:
            aui.Window(os.environ["ACTIONUI_WINDOW_UUID"]).set_string(2, "should not land")
        except aui.RemoteError as error:
            print("refused", error.code)
        """
        let wrong = try runPython(refused, extra: ["ACTIONUI_REMOTE_TOKEN": "not-the-token"])
        XCTAssertTrue(wrong.output.contains("refused 1006"), wrong.output)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2) as? String, "over the pipe")
    }

    /// Another computer's pipe, a file path and a name that is no pipe name are refused before
    /// anything is opened.
    func testOnlyLocalPipeNamesAreUsed() throws {
        let source = #"""
        import actionui_remote as aui
        for name in ["\\\\server\\pipe\\actionui-1", "//server/pipe/actionui-1", "C:\\Temp\\a.sock",
                     "\\\\.\\pipe\\a\\b", "\\\\.\\pipe\\a.", "\\\\.\\pipe\\"]:
            try:
                aui.Connection(name).call("actionui.hello")
                print("USED", name)
            except aui.EndpointError as error:
                print("refused:", error)
        print("done")
        """#
        let run = try runPython(source)
        XCTAssertEqual(run.status, 0, run.output)
        XCTAssertFalse(run.output.contains("USED"), run.output)
        // The check's own message: a failed connect is an EndpointError too, and must not count.
        XCTAssertEqual(run.output.components(separatedBy: "refused: not a local pipe name").count - 1, 6, run.output)
    }

    func testNothingListeningSaysSo() throws {
        let source = #"""
        import actionui_remote as aui
        try:
            aui.Connection("\\\\.\\pipe\\actionui-nobody-here").call("actionui.hello")
        except aui.EndpointError as error:
            print("refused:", error)
        """#
        let run = try runPython(source)
        XCTAssertTrue(run.output.contains("no ActionUI host is listening"), run.output)
    }

    /// The owner check: a pipe the user may open but does not own (the Administrators group owns
    /// it) gets no token. Only an elevated process can make such a pipe.
    func testAPipeThatIsNotTheUsersGetsNoToken() throws {
        guard let user = currentUserSIDText() else { throw XCTSkip("this process's user could not be read") }
        let name = makeTestEndpoint("aui-foreign")
        let sddl = "O:BAD:P(A;;GRGW;;;\(user))"
        var descriptor: PSECURITY_DESCRIPTOR? = nil
        guard sddl.withCString(encodedAs: UTF16.self, {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
        }), let descriptor else {
            throw XCTSkip("the security descriptor could not be made (Windows error \(GetLastError()))")
        }
        defer { LocalFree(descriptor) }
        var attributes = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                             lpSecurityDescriptor: descriptor, bInheritHandle: false)
        let handle = name.withCString(encodedAs: UTF16.self) {
            CreateNamedPipeW($0, DWORD(PIPE_ACCESS_DUPLEX), DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_WAIT), 2, 4096, 4096, 0,
                             &attributes)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw XCTSkip("only an elevated process can make a pipe the Administrators group owns (Windows error \(GetLastError()))")
        }
        defer { CloseHandle(handle) }

        let source = """
        import actionui_remote as aui
        try:
            aui.Connection(r"\(name)", token="secret").call("actionui.hello")
            print("USED")
        except aui.EndpointError as error:
            print("refused:", error)
        """
        let run = try runPython(source)
        XCTAssertFalse(run.output.contains("USED"), run.output)
        XCTAssertTrue(run.output.contains("belongs to another account"), run.output)
        // Nothing was written to the pipe: the token never left the client.
        var available: DWORD = 0
        _ = PeekNamedPipe(handle, nil, 0, nil, &available, nil)
        XCTAssertEqual(available, 0, "the client wrote to a pipe it does not trust")
    }
}

#endif
