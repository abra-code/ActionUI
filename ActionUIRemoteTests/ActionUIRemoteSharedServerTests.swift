// ActionUIRemoteTests/ActionUIRemoteSharedServerTests.swift
//
// The process-wide server: the API a host actually calls (OMC calls exactly this; the AppKit
// application adapter wraps it for its Python and Node bindings). These tests touch real
// process state - one singleton and one environment variable - so every one of them restores
// both, and the end-to-end case pumps the main run loop for the same reason as
// ActionUIRemoteServerTests: the server hops every request to the main queue.

#if os(macOS)

import XCTest
import Darwin
@testable import ActionUI
@testable import ActionUIRemote

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

@MainActor
final class ActionUIRemoteSharedServerTests: XCTestCase {

    private var savedEndpoint: String?
    private let clientQueue = DispatchQueue(label: "test.shared.client")

    override func setUp() async throws {
        try await super.setUp()
        ActionUIModel.resetForRemoteTests()
        let logger = QuietLogger(maxLevel: .warning)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        savedEndpoint = Self.environmentEndpoint()
        ActionUIRemoteServer.stopShared()          // no test may inherit a running server
    }

    override func tearDown() async throws {
        ActionUIRemoteServer.stopShared()
        if let savedEndpoint {
            setenv(ActionUIRemoteEnvironment.endpoint, savedEndpoint, 1)
        } else {
            unsetenv(ActionUIRemoteEnvironment.endpoint)
        }
        ActionUIModel.resetForRemoteTests()
        try await super.tearDown()
    }

    /// getenv, not ProcessInfo.environment, which is a snapshot taken at first use.
    private static func environmentEndpoint() -> String? {
        guard let raw = getenv(ActionUIRemoteEnvironment.endpoint) else { return nil }
        return String(cString: raw)
    }

    private func temporarySocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("aui-shared-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock").path
    }

    // MARK: - Lifecycle

    func testStartSharedBindsExportsAndReportsItsPath() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        host: .init(name: "SharedHost", version: "1.0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(ActionUIRemoteServer.sharedEndpoint, path)
        XCTAssertNotNil(ActionUIRemoteServer.shared)
        XCTAssertEqual(Self.environmentEndpoint(), path,
                       "children spawned after the start must inherit the endpoint")
    }

    func testTheDefaultPathIsOnePerProcessAndFitsSunPath() throws {
        let expected = ActionUIRemoteServer.defaultSocketPath()
        XCTAssertTrue(expected.contains("\(getpid())"), "one socket per process: \(expected)")
        XCTAssertLessThanOrEqual(expected.utf8.count, 103, "sun_path holds 103 bytes")

        let path = try ActionUIRemoteServer.startShared()
        XCTAssertEqual(path, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testStartingTwiceIsRefusedAndLeavesTheFirstServing() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())
        let first = ActionUIRemoteServer.shared

        XCTAssertThrowsError(try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())) { error in
            guard case UnixSocketServerError.alreadyStarted = error else {
                return XCTFail("expected alreadyStarted, got \(error)")
            }
        }
        XCTAssertIdentical(ActionUIRemoteServer.shared, first, "the running server is untouched")
        XCTAssertEqual(ActionUIRemoteServer.sharedEndpoint, path)
        XCTAssertEqual(Self.environmentEndpoint(), path)
    }

    func testStopSharedRemovesTheSocketAndTheVariable() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())
        ActionUIRemoteServer.stopShared()

        XCTAssertNil(ActionUIRemoteServer.shared)
        XCTAssertNil(ActionUIRemoteServer.sharedEndpoint)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "the socket file is removed")
        XCTAssertNil(Self.environmentEndpoint())
    }

    func testStoppingWhenNothingRunsKeepsAnInheritedEndpoint() {
        // A host that is itself a remote child inherited this variable from its parent. Stopping
        // a server this process never started must not take it away.
        setenv(ActionUIRemoteEnvironment.endpoint, "/inherited/from/a/parent.sock", 1)
        ActionUIRemoteServer.stopShared()
        XCTAssertEqual(Self.environmentEndpoint(), "/inherited/from/a/parent.sock")
    }

    func testStartAfterStopWorksAndRepointsTheVariable() throws {
        let first = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())
        ActionUIRemoteServer.stopShared()
        let second = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Self.environmentEndpoint(), second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second))
    }

    func testAFailedStartLeavesNothingBehind() {
        let tooLong = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
        XCTAssertThrowsError(try ActionUIRemoteServer.startShared(socketPath: tooLong))
        XCTAssertNil(ActionUIRemoteServer.shared, "no half-started server")
        XCTAssertNil(Self.environmentEndpoint(), "nothing exported")
        // The claim flag was released, so a good path still starts.
        XCTAssertNoThrow(try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath()))
    }

    func testCurrentProcessHostNamesSomething() {
        let host = ActionUIRemoteServer.currentProcessHost()
        XCTAssertFalse(host.name.isEmpty)
        XCTAssertFalse(host.version.isEmpty)
    }

    func testTheEnvironmentContractIsTheProtocolsNames() {
        XCTAssertEqual(ActionUIRemoteEnvironment.endpoint, "ACTIONUI_REMOTE_ENDPOINT")
        XCTAssertEqual(ActionUIRemoteEnvironment.windowUUID, "ACTIONUI_WINDOW_UUID")
    }

    // MARK: - The C face (what OMC calls)

    func testTheCEntryPointsDriveTheSameServer() throws {
        XCTAssertFalse(actionUIRemoteServerIsRunning())
        XCTAssertNil(actionUIRemoteServerEndpoint())

        let path = temporarySocketPath()
        let started = path.withCString { pathC in
            "COMCHost".withCString { nameC in
                "3.1".withCString { versionC in
                    actionUIRemoteStartServer(pathC, nameC, versionC)
                }
            }
        }
        XCTAssertTrue(started)
        XCTAssertTrue(actionUIRemoteServerIsRunning())
        XCTAssertEqual(actionUIRemoteServerEndpoint().map { String(cString: $0) }, path)
        XCTAssertEqual(ActionUIRemoteServer.sharedEndpoint, path, "the C face drives the shared server")
        XCTAssertEqual(ActionUIRemoteServer.shared?.host.name, "COMCHost")
        XCTAssertEqual(ActionUIRemoteServer.shared?.host.version, "3.1")
        XCTAssertEqual(Self.environmentEndpoint(), path)

        // Starting twice is refused through C too, as false rather than a throw.
        XCTAssertFalse(path.withCString { actionUIRemoteStartServer($0, nil, nil) })

        actionUIRemoteStopServer()
        XCTAssertFalse(actionUIRemoteServerIsRunning())
        XCTAssertNil(actionUIRemoteServerEndpoint())
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testTheCStartFallsBackToTheProcessHostAndDefaultPath() {
        XCTAssertTrue(actionUIRemoteStartServer(nil, nil, nil))
        XCTAssertEqual(actionUIRemoteServerEndpoint().map { String(cString: $0) },
                       ActionUIRemoteServer.defaultSocketPath())
        XCTAssertEqual(ActionUIRemoteServer.shared?.host.name,
                       ActionUIRemoteServer.currentProcessHost().name)
        actionUIRemoteStopServer()
    }

    // MARK: - It really serves

    func testTheSharedServerAnswersAndCarriesTheHostsOwnMethods() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        host: .init(name: "SharedHost", version: "2.5"),
                                                        logger: QuietLogger(maxLevel: .warning))
        // A host registers its methods on the shared instance; this is how OMC adds `omc.*`.
        let shared = try XCTUnwrap(ActionUIRemoteServer.shared)
        shared.register(method: "host.ping") { params in
            return ["pong": params["value"] ?? NSNull()]
        }

        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        let hello = try XCTUnwrap(exchangeJSON(client, #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello"}"#))
        let result = try XCTUnwrap(hello["result"] as? [String: Any])
        XCTAssertEqual((result["host"] as? [String: String])?["name"], "SharedHost")
        XCTAssertEqual((result["host"] as? [String: String])?["version"], "2.5")
        XCTAssertTrue((result["methods"] as? [String] ?? []).contains("host.ping"))

        let ping = try XCTUnwrap(exchangeJSON(client, #"{"jsonrpc":"2.0","id":2,"method":"host.ping","params":{"value":7}}"#))
        XCTAssertEqual((ping["result"] as? [String: Any])?["pong"] as? Int, 7)
    }

    /// Send one line and read the reply, with the client on a background queue while the main
    /// run loop is pumped: the server hops every request to the main queue, so a blocking read
    /// on main would starve it and every request would come back 1005.
    private func exchangeJSON(_ client: TestSocketClient, _ line: String) -> [String: Any]? {
        let box = ResultBox<String>()
        let done = expectation(description: "reply")
        clientQueue.async {
            client.write(line + "\n")
            box.value = client.readLine()
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        guard let text = box.value, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

#endif
