// ActionUIRemoteTests/NodeClientWindowsTests.swift
//
// The Node.js client on Windows (ActionUIRemote/Node/actionui_remote.js with actionui_remote_windows.js)
// against the real server over a named pipe: the token from the environment is sent and a wrong one
// refused, another computer's endpoint and other non-pipe names are refused before anything is
// opened, and a pipe nobody serves is reported as such. Skipped when Node is not installed.

#if os(Windows)

import XCTest
@testable import ActionUI
@testable import ActionUIRemote

/// A Node child that did not finish: a failure, not a skip, since a hang is what a regression in
/// the endpoint check (a connect to another computer's pipe) would look like.
private struct NodeTimedOut: Error, CustomStringConvertible {
    let output: String
    var description: String { "the Node child did not finish within 60 s:\n\(output)" }
}

private final class NodeOutput: @unchecked Sendable {
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

@MainActor
final class NodeClientWindowsTests: XCTestCase {

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
        endpoint = makeTestEndpoint("aui-node")
        server = ActionUIRemoteServer(host: .init(name: "NodeWindowsHost", version: "0.1"))
        server.logger = QuietLogger(maxLevel: .warning)
        try server.start(socketPath: endpoint)
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        ActionUIModel.resetForRemoteTests()
    }

    /// node.exe in a PATH folder, not the WindowsApps folder's stubs.
    private static func nodeExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PATH"] ?? environment["Path"] else { return nil }
        let fileManager = FileManager.default
        return path.split(separator: ";")
            .filter { !$0.lowercased().contains("\\windowsapps") }
            .map { String($0) + "\\node.exe" }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static var clientPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // ActionUIRemoteTests
            .deletingLastPathComponent()        // package root
            .appendingPathComponent("ActionUIRemote/Node/actionui_remote.js")
            .path
    }

    /// Runs `body` (JavaScript, inside an async function, with `aui` the client) under `node -e`,
    /// with the endpoint and window in the environment plus `extra`. The exit status and the output.
    private func runNode(_ body: String, extra: [String: String] = [:]) throws -> (status: Int32, output: String) {
        guard let node = Self.nodeExecutable() else {
            throw XCTSkip("Node.js is not installed on this machine")
        }
        let clientLiteral = Self.clientPath.replacingOccurrences(of: "\\", with: "\\\\")
        let source = """
        const aui = require("\(clientLiteral)");
        (async () => {
        \(body)
        })().then(() => process.exit(0), (error) => {
            console.log("error", error && error.name, error && error.code, error && error.message);
            process.exit(1);
        });
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: node)
        process.arguments = ["-e", source]
        var environment = ProcessInfo.processInfo.environment
        environment["ACTIONUI_REMOTE_ENDPOINT"] = endpoint
        environment["ACTIONUI_WINDOW_UUID"] = windowUUID
        environment.removeValue(forKey: "ACTIONUI_REMOTE_TOKEN")
        for (key, value) in extra {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = NodeOutput()
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
            throw NodeTimedOut(output: output.text)
        }
        return (process.terminationStatus, output.text)
    }

    func testTheTokenInTheEnvironmentIsSentAndAWrongOneRefused() throws {
        let token = ActionUIRemoteServer.makeToken()
        server.addToken(token, label: "child")
        server.requiresToken = true

        let run = try runNode("""
            const win = aui.Window.fromEnvironment();
            await win.setString(2, "over the pipe from node");
            console.log("ok", await win.getString(2));
            """, extra: ["ACTIONUI_REMOTE_TOKEN": token])
        XCTAssertEqual(run.status, 0, run.output)
        XCTAssertTrue(run.output.contains("ok over the pipe from node"), run.output)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2) as? String,
                       "over the pipe from node")

        let wrong = try runNode("""
            try {
                await aui.Window.fromEnvironment().setString(2, "should not land");
            } catch (error) {
                console.log("refused", error.code);
            }
            """, extra: ["ACTIONUI_REMOTE_TOKEN": "not-the-token"])
        XCTAssertTrue(wrong.output.contains("refused 1006"), wrong.output)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2) as? String,
                       "over the pipe from node")
    }

    /// Another computer's pipe, a file path and names that are no pipe names are refused before
    /// anything is opened.
    func testOnlyLocalPipeNamesAreUsed() throws {
        let run = try runNode(#"""
            for (const name of ["\\\\server\\pipe\\actionui-1", "//server/pipe/actionui-1", "C:\\Temp\\a.sock",
                                "\\\\.\\pipe\\a\\b", "\\\\.\\pipe\\a.", "\\\\.\\pipe\\"]) {
                try {
                    await aui.connect({ endpoint: name }).call("actionui.hello");
                    console.log("USED", name);
                } catch (error) {
                    console.log("refused:", error.name, error.message);
                }
            }
            """#)
        XCTAssertEqual(run.status, 0, run.output)
        XCTAssertFalse(run.output.contains("USED"), run.output)
        // The check's own message: a failed connect is an EndpointError too, so the name alone
        // would not show that nothing was opened.
        XCTAssertEqual(run.output.components(separatedBy: "refused: EndpointError not a local pipe name").count - 1,
                       6, run.output)
    }

    func testNothingListeningSaysSo() throws {
        let run = try runNode(#"""
            try {
                await aui.connect({ endpoint: "\\\\.\\pipe\\actionui-nobody-here" }).call("actionui.hello");
            } catch (error) {
                console.log("refused:", error.name, error.message);
            }
            """#)
        XCTAssertTrue(run.output.contains("no ActionUI host is listening"), run.output)
    }
}

#endif
