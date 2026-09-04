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
    private var savedToken: String?
    private let clientQueue = DispatchQueue(label: "test.shared.client")

    override func setUp() async throws {
        try await super.setUp()
        ActionUIModel.resetForRemoteTests()
        let logger = QuietLogger(maxLevel: .warning)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        savedEndpoint = Self.environmentEndpoint()
        savedToken = Self.environmentToken()
        ActionUIRemoteServer.stopShared()          // no test may inherit a running server
    }

    override func tearDown() async throws {
        ActionUIRemoteServer.stopShared()
        if let savedEndpoint {
            setenv(ActionUIRemoteEnvironment.endpoint, savedEndpoint, 1)
        } else {
            unsetenv(ActionUIRemoteEnvironment.endpoint)
        }
        if let savedToken {
            setenv(ActionUIRemoteEnvironment.token, savedToken, 1)
        } else {
            unsetenv(ActionUIRemoteEnvironment.token)
        }
        ActionUIModel.resetForRemoteTests()
        try await super.tearDown()
    }

    /// getenv, not ProcessInfo.environment, which is a snapshot taken at first use.
    private static func environmentEndpoint() -> String? {
        guard let raw = getenv(ActionUIRemoteEnvironment.endpoint) else { return nil }
        return String(cString: raw)
    }

    private static func environmentToken() -> String? {
        guard let raw = getenv(ActionUIRemoteEnvironment.token) else { return nil }
        return String(cString: raw)
    }

    /// The token the shared server exported, quoted for splicing into a raw JSON request.
    private func tokenParam() throws -> String {
        let token = try XCTUnwrap(Self.environmentToken(), "startShared should have exported a token")
        return "\"token\":\"\(token)\""
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

        // startShared requires a token now, so a raw client has to present one exactly as the
        // Python client does from the environment.
        let token = try tokenParam()
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        let hello = try XCTUnwrap(exchangeJSON(client,
            #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"# + token + "}}"))
        let result = try XCTUnwrap(hello["result"] as? [String: Any])
        XCTAssertEqual((result["host"] as? [String: String])?["name"], "SharedHost")
        XCTAssertEqual((result["host"] as? [String: String])?["version"], "2.5")
        XCTAssertTrue((result["methods"] as? [String] ?? []).contains("host.ping"))

        // No token on this one: the connection authenticated above and is remembered, which is
        // what keeps the per-request cost at zero for a long-lived client.
        let ping = try XCTUnwrap(exchangeJSON(client, #"{"jsonrpc":"2.0","id":2,"method":"host.ping","params":{"value":7}}"#))
        XCTAssertEqual((ping["result"] as? [String: Any])?["pong"] as? Int, 7)
    }

    // MARK: - The token

    func testStartSharedMintsAndExportsAToken() throws {
        try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())
        let token = try XCTUnwrap(Self.environmentToken())
        XCTAssertGreaterThanOrEqual(token.count, 32, "a guessable token is not a token")
        XCTAssertEqual(ActionUIRemoteServer.shared?.requiresToken, true)
        XCTAssertEqual(ActionUIRemoteServer.shared?.tokenLabels, ["host"])
    }

    func testOptingOutServesWithoutATokenAndExportsNone() throws {
        try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(), requireToken: false)
        XCTAssertEqual(ActionUIRemoteServer.shared?.requiresToken, false)
        XCTAssertNil(Self.environmentToken(), "a host that requires none must export none")
    }

    func testOptingOutClearsAnInheritedToken() throws {
        // A child of a token-using host that starts its own open server must not leave the
        // parent's token in its environment, where its own children would send it onward.
        setenv(ActionUIRemoteEnvironment.token, "inherited-from-a-parent", 1)
        try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(), requireToken: false)
        XCTAssertNil(Self.environmentToken())
    }

    func testStopSharedUnsetsTheToken() throws {
        try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())
        XCTAssertNotNil(Self.environmentToken())
        ActionUIRemoteServer.stopShared()
        XCTAssertNil(Self.environmentToken())
    }

    func testARequestWithNoTokenIsRefused() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        let reply = try XCTUnwrap(exchangeJSON(client, #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello"}"#))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, 1006)
        XCTAssertNil(reply["result"], "a refused request must not also answer")
    }

    func testAWrongTokenIsRefused() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        let reply = try XCTUnwrap(exchangeJSON(client,
            #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"token":"not-the-token"}}"#))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, 1006)
    }

    func testTheTokenNeverReachesAMethodHandler() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let seen = ResultBox<[String]>()
        let shared = try XCTUnwrap(ActionUIRemoteServer.shared)
        shared.register(method: "host.echoParams") { params in
            seen.value = params.keys.sorted()
            return true
        }

        let token = try tokenParam()
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        _ = exchangeJSON(client,
            #"{"jsonrpc":"2.0","id":1,"method":"host.echoParams","params":{"a":1,"# + token + "}}")

        // A host extension is third-party code; it has no business seeing a credential that was
        // not addressed to it.
        XCTAssertEqual(seen.value, ["a"], "the token must be stripped before dispatch")
    }

    func testRevokingATokenStopsANewConnection() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let token = try XCTUnwrap(Self.environmentToken())
        let param = try tokenParam()

        let first = try TestSocketClient(path: path, timeoutSeconds: 10)
        let before = try XCTUnwrap(exchangeJSON(first,
            #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"# + param + "}}"))
        XCTAssertNotNil(before["result"])

        ActionUIRemoteServer.shared?.revokeToken(token)
        XCTAssertEqual(ActionUIRemoteServer.shared?.tokenLabels, [])

        let second = try TestSocketClient(path: path, timeoutSeconds: 10)
        let after = try XCTUnwrap(exchangeJSON(second,
            #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"# + param + "}}"))
        XCTAssertEqual((after["error"] as? [String: Any])?["code"] as? Int, 1006)
    }

    func testAnUnauthenticatedNotificationIsDroppedWithoutAReply() throws {
        // A notification asks for no reply, so refusing it must not invent one - a client that
        // sent a notification and then a real request would read the refusal as the reply to
        // the request and mismatch every id after it.
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let token = try tokenParam()
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)

        let reply = try XCTUnwrap(exchangeAfterNotification(
            client,
            notification: #"{"jsonrpc":"2.0","method":"actionui.listWindows"}"#,
            then: #"{"jsonrpc":"2.0","id":9,"method":"actionui.hello","params":{"# + token + "}}"))
        XCTAssertEqual(reply["id"] as? Int, 9, "the only line back is the answer to the request")
        XCTAssertNotNil(reply["result"])
    }

    func testATokenOnTheFirstBatchEntryCoversTheWholeBatch() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let token = try tokenParam()
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)

        let batch = "[" + #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"# + token + "}},"
                        + #"{"jsonrpc":"2.0","id":2,"method":"actionui.listWindows"}"# + "]"
        let raw = try XCTUnwrap(exchangeRaw(client, batch))
        let replies = try XCTUnwrap(raw as? [[String: Any]])
        XCTAssertEqual(replies.count, 2)
        for reply in replies {
            XCTAssertNil(reply["error"], "the whole batch rides the token on its first entry")
        }
    }

    func testAnUnauthenticatedBatchIsRefusedEntryByEntry() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        let batch = "[" + #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello"},"#
                        + #"{"jsonrpc":"2.0","id":2,"method":"actionui.listWindows"}"# + "]"
        let raw = try XCTUnwrap(exchangeRaw(client, batch))
        let replies = try XCTUnwrap(raw as? [[String: Any]])
        XCTAssertEqual(replies.count, 2)
        for reply in replies {
            XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, 1006)
        }
    }

    func testARestartedServerDoesNotInheritAuthentication() throws {
        // Connection ids are per socket server and restart at 1. A stopped server's connections
        // may never deliver onClose - it holds its server weakly - so without clearing the set
        // on start, connection 1 of the second run would arrive already authenticated.
        let server = ActionUIRemoteServer(host: .init(name: "Restart", version: "1"))
        server.logger = QuietLogger(maxLevel: .warning)
        server.requiresToken = true
        server.addToken("the-token", label: "test")

        let firstPath = temporarySocketPath()
        try server.start(socketPath: firstPath)
        do {
            // Scoped so the client's deinit closes the descriptor before the restart below.
            let first = try TestSocketClient(path: firstPath, timeoutSeconds: 10)
            let authenticated = try XCTUnwrap(exchangeJSON(first,
                #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"token":"the-token"}}"#))
            XCTAssertNotNil(authenticated["result"], "connection 1 of the first run authenticates")
        }
        server.stop()

        let secondPath = temporarySocketPath()
        try server.start(socketPath: secondPath)
        defer { server.stop() }
        let second = try TestSocketClient(path: secondPath, timeoutSeconds: 10)
        let reply = try XCTUnwrap(exchangeJSON(second,
            #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello"}"#))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, 1006,
                       "connection 1 of the second run must start unauthenticated")
    }

    func testATokenIsStrippedEvenWhenNoneIsRequired() throws {
        // The not-required path strips too: a stray token must never reach a handler, and that
        // branch had no coverage.
        let server = ActionUIRemoteServer(host: .init(name: "Open", version: "1"))
        server.logger = QuietLogger(maxLevel: .warning)
        XCTAssertFalse(server.requiresToken)
        let seen = ResultBox<[String]>()
        server.register(method: "host.echoParams") { params in
            seen.value = params.keys.sorted()
            return true
        }
        let path = temporarySocketPath()
        try server.start(socketPath: path)
        defer { server.stop() }

        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        _ = exchangeJSON(client,
            #"{"jsonrpc":"2.0","id":1,"method":"host.echoParams","params":{"a":1,"token":"stray"}}"#)
        XCTAssertEqual(seen.value, ["a"])
    }

    func testAWrongTokenThenTheRightOneOnTheSameConnection() throws {
        let path = try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath(),
                                                        logger: QuietLogger(maxLevel: .warning))
        let client = try TestSocketClient(path: path, timeoutSeconds: 10)
        let refused = try XCTUnwrap(exchangeJSON(client,
            #"{"jsonrpc":"2.0","id":1,"method":"actionui.hello","params":{"token":"wrong"}}"#))
        XCTAssertEqual((refused["error"] as? [String: Any])?["code"] as? Int, 1006)

        // A refusal must not poison the connection: the client may simply try again.
        let accepted = try XCTUnwrap(exchangeJSON(client,
            #"{"jsonrpc":"2.0","id":2,"method":"actionui.hello","params":{"# + (try tokenParam()) + "}}"))
        XCTAssertNotNil(accepted["result"])
    }

    func testTheCAccessorAgreesWithTheEnvironment() throws {
        // A binding whose runtime snapshots the environment at startup - CPython does - cannot
        // read the token from os.environ. This is how it gets an exact answer instead.
        XCTAssertNil(actionUIRemoteServerToken(), "nothing running, nothing to report")

        let path = temporarySocketPath()
        XCTAssertTrue(path.withCString { actionUIRemoteStartServer($0, nil, nil) })
        let fromC = try XCTUnwrap(actionUIRemoteServerToken().map { String(cString: $0) })
        XCTAssertEqual(fromC, Self.environmentToken())
        XCTAssertGreaterThanOrEqual(fromC.count, 32)

        actionUIRemoteStopServer()
        XCTAssertNil(actionUIRemoteServerToken(), "stopping clears it")
    }

    func testMakeTokenIsRandomAndLongEnough() {
        let tokens = (0..<64).map { _ in ActionUIRemoteServer.makeToken() }
        XCTAssertEqual(Set(tokens).count, tokens.count, "64 tokens, 64 distinct values")
        for token in tokens {
            XCTAssertEqual(token.count, 64, "32 bytes, hex encoded")
            XCTAssertNil(token.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted))
        }
    }

    func testManyTokensAreLiveAtOnceAndRevokeIndependently() throws {
        try ActionUIRemoteServer.startShared(socketPath: temporarySocketPath())
        let shared = try XCTUnwrap(ActionUIRemoteServer.shared)
        // The shape OMC needs: one grant per command, withdrawn when that command ends.
        for index in 0..<4 {
            shared.addToken(ActionUIRemoteServer.makeToken(), label: "command\(index)")
        }
        XCTAssertEqual(shared.tokenLabels, ["command0", "command1", "command2", "command3", "host"])
        shared.revokeTokens(label: "command2")
        XCTAssertEqual(shared.tokenLabels, ["command0", "command1", "command3", "host"])
    }

    /// Send a notification, then a request, and return the single line that comes back.
    private func exchangeAfterNotification(_ client: TestSocketClient,
                                           notification: String, then request: String) -> [String: Any]? {
        let box = ResultBox<String>()
        let done = expectation(description: "reply")
        clientQueue.async {
            client.write(notification + "\n")
            client.write(request + "\n")
            box.value = client.readLine()
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        guard let text = box.value, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Like exchangeJSON but returns whatever JSON came back, array or object.
    private func exchangeRaw(_ client: TestSocketClient, _ line: String) -> Any? {
        let box = ResultBox<String>()
        let done = expectation(description: "reply")
        clientQueue.async {
            client.write(line + "\n")
            box.value = client.readLine()
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        guard let text = box.value, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
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
