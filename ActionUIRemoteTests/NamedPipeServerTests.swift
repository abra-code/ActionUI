// ActionUIRemoteTests/NamedPipeServerTests.swift
//
// The remote server's transport on Windows, and each way it keeps others out: the pipe's name is not
// joined, other computers are refused, a client below the server's integrity level cannot open the
// pipe, and the server reads each client's identity before using anything it sent (an anonymous
// client and a restricted token are refused). Another user cannot be made here; the user check is the
// same comparison the restricted token goes through first.

#if os(Windows)

import XCTest
import WinSDK
@testable import ActionUI
@testable import ActionUIRemote

private final class LineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

/// This process's token, duplicated as an impersonation token the test may change.
private func duplicateOwnToken() throws -> HANDLE {
    var process: HANDLE? = nil
    guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_DUPLICATE) | DWORD(TOKEN_QUERY), &process), let process else {
        throw NamedPipeServerError.systemCall("OpenProcessToken", code: GetLastError())
    }
    defer { CloseHandle(process) }
    var duplicate: HANDLE? = nil
    let access = DWORD(TOKEN_QUERY) | DWORD(TOKEN_IMPERSONATE) | DWORD(TOKEN_ADJUST_DEFAULT) | DWORD(TOKEN_DUPLICATE)
    guard DuplicateTokenEx(process, access, nil, SecurityImpersonation, TokenImpersonation, &duplicate), let duplicate else {
        throw NamedPipeServerError.systemCall("DuplicateTokenEx", code: GetLastError())
    }
    return duplicate
}

/// Runs `body` while the calling thread acts as `token`, and reverts after.
private func whileActing<T>(as token: HANDLE, _ body: () -> T) throws -> T {
    guard SetThreadToken(nil, token) else {
        throw NamedPipeServerError.systemCall("SetThreadToken", code: GetLastError())
    }
    defer {
        if !RevertToSelf() {
            fatalError("RevertToSelf failed in a test (Windows error \(GetLastError()))")
        }
    }
    return body()
}

/// A raw pipe instance for comparison: Windows' default security, with or without the remote refusal.
private func makePlainPipe(_ name: String, rejectRemote: Bool) -> HANDLE? {
    var mode = DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_READMODE_BYTE) | DWORD(PIPE_WAIT)
    if rejectRemote {
        mode |= DWORD(PIPE_REJECT_REMOTE_CLIENTS)
    }
    let handle = name.withCString(encodedAs: UTF16.self) {
        CreateNamedPipeW($0, DWORD(PIPE_ACCESS_DUPLEX), mode, 4, 4096, 4096, 0, nil)
    }
    guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
    return handle
}

/// `\\.\pipe\x` as another computer would name it on this one: `\\localhost\pipe\x`.
private func throughTheNetwork(_ name: String) -> String {
    return "\\\\localhost\\pipe\\" + name.dropFirst(NamedPipeServer.localPrefix.count)
}

final class NamedPipeServerTests: XCTestCase {

    private func makeEchoServer(_ name: String, lines: LineLog) -> NamedPipeServer {
        let box = ServerBox()
        let server = NamedPipeServer(path: name, onLine: { id, line in
            let text = String(decoding: line, as: UTF8.self)
            lines.add(text)
            box.server?.send(connectionID: id, data: Data("echo \(text)".utf8))
        })
        box.server = server
        return server
    }

    private final class ServerBox: @unchecked Sendable {
        weak var server: NamedPipeServer?
    }

    func testLinesComeBackInOrder() throws {
        let name = makeTestEndpoint("aui-pipe")
        let lines = LineLog()
        let server = makeEchoServer(name, lines: lines)
        try server.start()
        defer { server.stop() }

        let client = try TestSocketClient(path: name)
        client.write("first\nsecond\r\n")
        XCTAssertEqual(client.readLine(), "echo first")
        XCTAssertEqual(client.readLine(), "echo second")
        XCTAssertEqual(lines.all, ["first", "second"])
        XCTAssertEqual(server.connectionCount, 1)
    }

    func testOnlyLocalPipeNamesAreTaken() {
        for name in ["\\\\.\\pipe\\actionui-1", "\\\\.\\PIPE\\a.b_c-d"] {
            XCTAssertTrue(NamedPipeServer.isLocalPipeName(name), name)
        }
        for name in ["\\\\host\\pipe\\x", "\\\\.\\pipe\\", "\\\\.\\pipe\\a\\b", "C:\\Temp\\a.sock", "/tmp/a.sock",
                     "\\\\.\\pipe\\a b", "\\\\.\\pipe\\a.", "\\\\.\\pipe\\..", "\\\\.\\pipe\\" + String(repeating: "a", count: 300)] {
            XCTAssertFalse(NamedPipeServer.isLocalPipeName(name), name)
            let server = NamedPipeServer(path: name, onLine: { _, _ in })
            XCTAssertThrowsError(try server.start(), name) { error in
                guard case NamedPipeServerError.invalidName = error else {
                    return XCTFail("\(name): \(error)")
                }
            }
        }
    }

    /// FILE_FLAG_FIRST_PIPE_INSTANCE: a second server, or a pipe somebody made first, is not joined.
    func testANameInUseIsNotJoined() throws {
        let name = makeTestEndpoint("aui-pipe")
        let first = NamedPipeServer(path: name, onLine: { _, _ in })
        try first.start()
        defer { first.stop() }
        let second = NamedPipeServer(path: name, onLine: { _, _ in })
        XCTAssertThrowsError(try second.start()) { error in
            guard case NamedPipeServerError.nameTaken = error else { return XCTFail("\(error)") }
        }

        let squatted = makeTestEndpoint("aui-pipe")
        let squatter = try XCTUnwrap(makePlainPipe(squatted, rejectRemote: false))
        defer { CloseHandle(squatter) }
        let late = NamedPipeServer(path: squatted, onLine: { _, _ in })
        XCTAssertThrowsError(try late.start()) { error in
            guard case NamedPipeServerError.nameTaken = error else { return XCTFail("\(error)") }
        }
    }

    /// PIPE_REJECT_REMOTE_CLIENTS and the denied network sign-in: the pipe cannot be opened as
    /// \\localhost\pipe\name, which goes through the network as another computer's open would. A
    /// plain pipe shows first that the path works here.
    func testOtherComputersAreRefused() throws {
        let plainName = makeTestEndpoint("aui-plain")
        let plain = try XCTUnwrap(makePlainPipe(plainName, rejectRemote: false))
        defer { CloseHandle(plain) }
        let (control, controlError) = openPipe(throughTheNetwork(plainName), access: DWORD(GENERIC_READ))
        guard let control else {
            throw XCTSkip("pipes are not reachable through the network here (Windows error \(controlError)), so the refusal cannot be told apart")
        }
        CloseHandle(control)

        let flaggedName = makeTestEndpoint("aui-flagged")
        let flagged = try XCTUnwrap(makePlainPipe(flaggedName, rejectRemote: true))
        defer { CloseHandle(flagged) }
        let (flaggedOpen, flaggedError) = openPipe(throughTheNetwork(flaggedName), access: DWORD(GENERIC_READ))
        XCTAssertNil(flaggedOpen, "PIPE_REJECT_REMOTE_CLIENTS let a network client in")
        if let flaggedOpen { CloseHandle(flaggedOpen) }
        print("a pipe that rejects remote clients answered a network open with Windows error \(flaggedError)")

        let name = makeTestEndpoint("aui-pipe")
        let server = NamedPipeServer(path: name, onLine: { _, _ in })
        try server.start()
        defer { server.stop() }
        let (served, servedError) = openPipe(throughTheNetwork(name), access: DWORD(GENERIC_READ))
        XCTAssertNil(served, "the server's pipe let a network client in")
        if let served { CloseHandle(served) }
        print("the server's pipe answered a network open with Windows error \(servedError)")
        let (local, _) = openPipe(name)
        XCTAssertNotNil(local, "the local name must still open")
        if let local { CloseHandle(local) }
    }

    /// The integrity label: a client at Low cannot open the pipe at all.
    func testALowerIntegrityLevelCannotOpenThePipe() throws {
        let name = makeTestEndpoint("aui-pipe")
        let lines = LineLog()
        let server = makeEchoServer(name, lines: lines)
        try server.start()
        defer { server.stop() }

        let token = try duplicateOwnToken()
        defer { CloseHandle(token) }
        var lowSID: PSID? = nil
        XCTAssertTrue("S-1-16-4096".withCString(encodedAs: UTF16.self) { ConvertStringSidToSidW($0, &lowSID) })
        defer { LocalFree(lowSID) }
        var label = TOKEN_MANDATORY_LABEL(Label: SID_AND_ATTRIBUTES(Sid: lowSID, Attributes: DWORD(SE_GROUP_INTEGRITY)))
        let size = DWORD(MemoryLayout<TOKEN_MANDATORY_LABEL>.size) + GetLengthSid(lowSID)
        XCTAssertTrue(SetTokenInformation(token, TokenIntegrityLevel, &label, size), "Windows error \(GetLastError())")

        let (opened, code) = try whileActing(as: token) { openPipe(name) }
        XCTAssertNil(opened, "a Low client opened the pipe")
        if let opened { CloseHandle(opened) }
        XCTAssertEqual(code, DWORD(ERROR_ACCESS_DENIED))
        XCTAssertEqual(lines.all, [])
    }

    /// The server's own check: a client that lets the server know nothing of it is closed before
    /// anything it sent is used.
    func testAnAnonymousClientIsRefused() throws {
        let name = makeTestEndpoint("aui-pipe")
        let lines = LineLog()
        let server = makeEchoServer(name, lines: lines)
        try server.start()
        defer { server.stop() }

        let client = try TestSocketClient(path: name, identity: .anonymous)
        client.write("hello\n")
        XCTAssertTrue(client.waitForEOF(), "the server should close an anonymous client")
        XCTAssertEqual(lines.all, [])
    }

    /// The server's own check: a restricted token of the same user passes the pipe's access list
    /// (its restricting SID is the user) and is refused by the server, before its line is used.
    func testARestrictedTokenIsRefused() throws {
        let name = makeTestEndpoint("aui-pipe")
        let lines = LineLog()
        let server = makeEchoServer(name, lines: lines)
        try server.start()
        defer { server.stop() }

        var process: HANDLE? = nil
        XCTAssertTrue(OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY) | DWORD(TOKEN_DUPLICATE), &process))
        let processToken = try XCTUnwrap(process)
        defer { CloseHandle(processToken) }
        var size: DWORD = 0
        _ = GetTokenInformation(processToken, TokenUser, nil, 0, &size)
        let user = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { user.deallocate() }
        XCTAssertTrue(GetTokenInformation(processToken, TokenUser, user, size, &size))
        var restricting = [SID_AND_ATTRIBUTES(Sid: user.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, Attributes: 0)]
        var restricted: HANDLE? = nil
        XCTAssertTrue(CreateRestrictedToken(processToken, 0, 0, nil, 0, nil, DWORD(restricting.count), &restricting, &restricted),
                      "Windows error \(GetLastError())")
        let primary = try XCTUnwrap(restricted)
        defer { CloseHandle(primary) }
        var impersonation: HANDLE? = nil
        XCTAssertTrue(DuplicateTokenEx(primary, DWORD(TOKEN_QUERY) | DWORD(TOKEN_IMPERSONATE), nil, SecurityImpersonation,
                                       TokenImpersonation, &impersonation))
        let token = try XCTUnwrap(impersonation)
        defer { CloseHandle(token) }

        // The identity is taken when the pipe is opened, so the client goes on as the restricted token.
        let client = try whileActing(as: token) { try? TestSocketClient(path: name) }
        let opened = try XCTUnwrap(client, "a restricted token of the user should pass the access list")
        opened.write("hello\n")
        XCTAssertTrue(opened.waitForEOF(), "the server should close a restricted client")
        XCTAssertEqual(lines.all, [])
    }

    /// A modal's file must be named from a local drive's root: not a network or device path, whose
    /// open would reach a server or a device.
    func testOnlyLocalDrivePathsAreAbsolute() {
        for path in ["C:\\Temp\\modal.json", "c:/Users/modal.json", "Z:\\a"] {
            XCTAssertTrue(isAbsoluteLocalPath(path), path)
        }
        for path in ["\\\\server\\share\\modal.json", "//server/share/modal.json", "\\\\.\\pipe\\x",
                     "\\\\?\\C:\\modal.json", "\\modal.json", "C:modal.json", "/tmp/modal.json", "modal.json", "C:"] {
            XCTAssertFalse(isAbsoluteLocalPath(path), path)
        }
    }

    /// The shared server on Windows: a fresh pipe name per start, the host's token kept for the C
    /// functions, and nothing put in the environment.
    func testTheSharedServerExportsNothing() throws {
        let endpointBefore = environmentValue(ActionUIRemoteEnvironment.endpoint)
        let tokenBefore = environmentValue(ActionUIRemoteEnvironment.token)
        let name = try ActionUIRemoteServer.startShared(host: .init(name: "Shared", version: "0.1"))
        defer { ActionUIRemoteServer.stopShared() }
        XCTAssertTrue(NamedPipeServer.isLocalPipeName(name), name)
        XCTAssertTrue(name.hasPrefix("\\\\.\\pipe\\actionui-\(GetCurrentProcessId())-"), name)
        XCTAssertEqual(ActionUIRemoteServer.sharedEndpoint, name)
        XCTAssertEqual(ActionUIRemoteServer.sharedStartupToken?.count, 64)
        XCTAssertEqual(environmentValue(ActionUIRemoteEnvironment.endpoint), endpointBefore)
        XCTAssertEqual(environmentValue(ActionUIRemoteEnvironment.token), tokenBefore)
        XCTAssertThrowsError(try ActionUIRemoteServer.startShared())

        ActionUIRemoteServer.stopShared()
        XCTAssertNil(ActionUIRemoteServer.sharedEndpoint)
        XCTAssertNil(ActionUIRemoteServer.sharedStartupToken)
        let again = try ActionUIRemoteServer.startShared(host: .init(name: "Shared", version: "0.1"))
        XCTAssertNotEqual(again, name)
    }
}

#endif
