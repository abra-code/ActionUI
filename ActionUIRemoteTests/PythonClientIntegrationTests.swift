// ActionUIRemoteTests/PythonClientIntegrationTests.swift
//
// The Python client against the real server. A headless window is loaded into
// ActionUIModel.shared, a real ActionUIRemoteServer is started on a real socket, and
// ActionUIRemote/Python/test_live_client.py is run as a child process against it. The script
// asserts everything it can see over the wire and exits non-zero on any mismatch; this test
// asserts its exit status and then re-reads the state it left behind through ActionUIModel, so
// a disagreement between what the wire reported and what the engine holds cannot pass unnoticed.
//
// The child is waited for with a terminationHandler and an expectation, never waitUntilExit():
// the server hops every request to the main queue, so blocking the main thread here would
// starve the script's very first call and every request would come back 1005.

#if os(macOS)

import XCTest
import Darwin
@testable import ActionUI
@testable import ActionUIRemote

/// Accumulates the child's merged stdout and stderr from the pipe's background queue.
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

/// A failure to run the script at all, thrown rather than reported with XCTFail so that one
/// clear message stands instead of a cascade from every assertion that follows.
private enum ScriptRunFailure: Error, LocalizedError, CustomStringConvertible {
    case missing(String)
    case timedOut(TimeInterval, String)

    var description: String {
        switch self {
        case .missing(let path):
            return "test_live_client.py is missing at \(path)"
        case .timedOut(let timeout, let output):
            return "test_live_client.py did not finish within \(timeout) s:\n\(output)"
        }
    }

    var errorDescription: String? { description }
}

@MainActor
final class PythonClientIntegrationTests: XCTestCase {

    private var socketPath: String!
    private var windowUUID: String!
    private var server: ActionUIRemoteServer!

    override func setUp() async throws {
        try await super.setUp()
        ActionUIModel.resetForRemoteTests()
        let logger = QuietLogger(maxLevel: .warning)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger

        windowUUID = UUID().uuidString
        try loadFixtureWindow(uuid: windowUUID)

        socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("aui-py-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock").path
        server = ActionUIRemoteServer(host: .init(name: Self.hostName, version: "0.1"))
        server.logger = logger
        try server.start(socketPath: socketPath)
    }

    override func tearDown() async throws {
        server?.stop()
        server = nil
        unlink(socketPath)
        ActionUIModel.resetForRemoteTests()
        try await super.tearDown()
    }

    // MARK: - Fixture

    /// The same window as ActionUIRemoteServerTests, because test_live_client.py is written
    /// against it: VStack 10 containing TextField 2, Toggle 3, Table 5 (two columns),
    /// DatePicker 6, Grid 7 with one row, Text 11.
    private func loadFixtureWindow(uuid: String) throws {
        let description: [String: Any] = [
            "id": 10,
            "type": "VStack",
            "children": [
                ["id": 2, "type": "TextField", "properties": ["title": "Name"]],
                ["id": 3, "type": "Toggle", "properties": ["title": "On"]],
                ["id": 5, "type": "Table", "properties": ["itemType": ["viewType": "Text"], "columns": ["A", "B"]]],
                ["id": 6, "type": "DatePicker", "properties": ["title": "When"]],
                ["id": 7, "type": "Grid", "rows": [[["id": 70, "type": "Text", "properties": ["text": "r0c0"]]]]],
                ["id": 11, "type": "Text", "properties": ["text": "hello"]],
            ],
        ]
        _ = try ActionUIModel.shared.loadDescription(from: description, windowUUID: uuid)
    }

    // MARK: - Locating the interpreter and the script

    /// The first python3 on PATH, then the usual fixed locations. PATH first because that is
    /// what a `#!/usr/bin/env python3` handler would pick up.
    private static func pythonExecutable() -> String? {
        let fileManager = FileManager.default
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { String($0) + "/python3" })
        }
        candidates.append(contentsOf: ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"])
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// ActionUIRemote/Python/test_live_client.py, resolved from this file rather than from the
    /// working directory, which `swift test` does not promise.
    private static var scriptPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // ActionUIRemoteTests
            .deletingLastPathComponent()        // package root
            .appendingPathComponent("ActionUIRemote/Python/test_live_client.py")
            .path
    }

    // MARK: - Running the script

    private static let hostName = "PythonIntegrationHost"

    private func runScript(windowUUID uuid: String, timeout: TimeInterval = 120) throws -> (status: Int32, output: String) {
        guard let python = Self.pythonExecutable() else {
            throw XCTSkip("python3 is not available on this machine")
        }
        let script = Self.scriptPath
        guard FileManager.default.isReadableFile(atPath: script) else {
            throw ScriptRunFailure.missing(script)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, socketPath, uuid, Self.hostName]
        var environment = ProcessInfo.processInfo.environment
        environment["ACTIONUI_REMOTE_ENDPOINT"] = socketPath
        environment["ACTIONUI_WINDOW_UUID"] = uuid
        environment["PYTHONDONTWRITEBYTECODE"] = "1"     // no __pycache__ in the source tree
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
        let outcome = XCTWaiter().wait(for: [exited, drained], timeout: timeout)
        guard outcome == .completed else {
            // terminationStatus raises on a process that is still running, so the child is
            // killed and the handler torn down before anything reads its status.
            process.terminate()
            pipe.fileHandleForReading.readabilityHandler = nil
            throw ScriptRunFailure.timedOut(timeout, output.text)
        }
        return (process.terminationStatus, output.text)
    }

    // MARK: - Tests

    func testPythonClientDrivesTheEngineAndLeavesTheStateItClaims() throws {
        let run = try runScript(windowUUID: windowUUID)
        XCTAssertEqual(run.status, 0, "test_live_client.py failed:\n\(run.output)")

        // The script's own summary, so that a run which exits 0 after checking almost nothing
        // (an early return, a renamed helper) fails here rather than reading as a pass. Located
        // by its prefix, not as the last line, so a late stderr line cannot displace it.
        let summary = run.output.split(separator: "\n").last { $0.hasPrefix("live client:") }.map(String.init) ?? ""
        let counts = summary.split(separator: " ").compactMap { Int($0) }
        XCTAssertEqual(counts.count, 2, "no usable summary line in:\n\(run.output)")
        XCTAssertEqual(counts.last, 0, "test_live_client.py reported failures:\n\(run.output)")
        XCTAssertGreaterThan(counts.first ?? 0, 95, "the script must actually run its checks: \(summary)")

        // Everything below is the state the script's docstring promises, read back through the
        // engine rather than over the wire.
        let model = ActionUIModel.shared
        XCTAssertEqual(model.getElementValue(windowUUID: windowUUID, viewID: 2) as? String, "final text")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "count") as? Int, 7,
                       "a state written from the wire is stored Swift-native")
        XCTAssertEqual(model.getElementValue(windowUUID: windowUUID, viewID: 3) as? Bool, true)
        XCTAssertEqual(model.getElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "disabled") as? Bool, true)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 5), [["x1", "y1"], ["x2", "y2"]])
        XCTAssertTrue(model.hasElement(windowUUID: windowUUID, viewID: 301), "the element inserted from Python is in the tree")
        XCTAssertTrue(model.hasElement(windowUUID: windowUUID, viewID: 310), "the Grid row inserted from Python is in the tree")
        XCTAssertTrue(model.hasElement(windowUUID: windowUUID, viewID: 311))
        XCTAssertFalse(model.hasElement(windowUUID: windowUUID, viewID: 300), "the element the script removed is gone")

        let windowModel = try XCTUnwrap(model.windowModels[windowUUID])
        XCTAssertEqual(windowModel.windowToast?.message, "done from python",
                       "the toast up at the end must be the last one, not one that was never dismissed")
        XCTAssertTrue(windowModel.toastQueue.isEmpty, "no toast was left queued behind another")
        XCTAssertNil(windowModel.windowModal, "every modal the script presented was dismissed")
        XCTAssertNil(windowModel.windowDialog, "every dialog the script presented was dismissed")
    }

    /// The harness must be able to fail. Pointed at a window that does not exist, the same
    /// script has to report failures and exit non-zero; without this, a green run of the test
    /// above would prove only that python3 exists.
    func testTheScriptReportsAFailureRatherThanPassingVacuously() throws {
        let run = try runScript(windowUUID: "no-such-window")
        XCTAssertNotEqual(run.status, 0, "the script must fail against a window that is not loaded")
        XCTAssertTrue(run.output.contains("FAIL:"), run.output)
    }
}

#endif
