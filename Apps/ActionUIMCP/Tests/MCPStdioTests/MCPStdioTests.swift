// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

import Foundation
import Testing
@testable import MCPStdio

/// Collects the server's output lines.
private final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [JSONValue] = []

    func append(_ data: Data) {
        let object = try? JSONSerialization.jsonObject(with: data)
        lock.withLock { lines.append(JSONValue(any: object)) }
    }

    var messages: [JSONValue] { lock.withLock { lines } }

    func response(id: JSONValue) -> JSONValue? {
        messages.first { $0["id"] == id && $0["method"] == nil }
    }
}

/// Resumable gate a test tool waits on.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private func makeServer(tools: [MCPTool]) -> (MCPServer, Sink) {
    let sink = Sink()
    let server = MCPServer(name: "test", version: "1", tools: tools, output: { sink.append($0) })
    return (server, sink)
}

private let echoTool = MCPTool(name: "echo", description: "echo", inputSchema: ["type": "object"],
                               outputSchema: ["type": "object"]) { arguments, context in
    .structured(["arguments": .object(arguments), "client": context.clientName.map(JSONValue.string) ?? .null])
}

private func line(_ value: JSONValue) -> String { value.serialized() }

@Test func initializeNegotiatesVersion() {
    let (server, sink) = makeServer(tools: [])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 3, "method": "initialize", "params": ["protocolVersion": 7]]))
    server.flush()
    #expect(sink.response(id: 1)?["result"]?["protocolVersion"] == "2025-06-18")
    #expect(sink.response(id: 2)?["result"]?["protocolVersion"] == .string(MCPServer.legacyProtocolVersions[0]))
    #expect(sink.response(id: 3)?["result"]?["protocolVersion"] == .string(MCPServer.legacyProtocolVersions[0]))
}

@Test func errorsFollowJSONRPC() {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: "not json")
    server.handle(line: "[1, 2]")
    server.handle(line: line(["jsonrpc": "2.0", "id": 5, "method": "nope"]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": ["name": "missing"]]))
    server.handle(line: line(["jsonrpc": "2.0", "method": "nope"]))  // notification: never answered
    server.flush()
    let codes = sink.messages.compactMap { $0["error"]?["code"] }
    #expect(codes == [-32700, -32600, -32601, -32602])
}

@Test func structuredContentIsGatedOnVersion() async {
    for (version, expectStructured) in [("2024-11-05", false), ("2025-11-25", true)] {
        let (server, sink) = makeServer(tools: [echoTool])
        server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                  "params": ["protocolVersion": .string(version), "clientInfo": ["name": "c"]]]))
        server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
        server.handle(line: line(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                                  "params": ["name": "echo", "arguments": ["a": 1]]]))
        await server.waitUntilIdle()
        server.flush()
        let tool = sink.response(id: 2)?["result"]?["tools"]?.array?.first
        #expect((tool?["outputSchema"] != nil) == expectStructured)
        let result = sink.response(id: 3)?["result"]
        #expect((result?["structuredContent"] != nil) == expectStructured)
        // The text block always carries the same object, for clients without structured content.
        let text = result?["content"]?.array?.first?["text"]?.string ?? ""
        let expected: JSONValue = ["arguments": ["a": 1], "client": "c"]
        #expect(text == expected.serialized())
    }
}

@Test func slowCallDoesNotBlockOthersAndCancelSuppressesResponse() async {
    let gate = Gate()
    let slow = MCPTool(name: "slow", description: "slow", inputSchema: ["type": "object"]) { _, _ in
        await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            Task { await gate.open() }
        }
        return .structured(["done": true])
    }
    let (server, sink) = makeServer(tools: [slow, echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "slow"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "echo"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 3, "method": "ping"]))
    // Wait for the echo answer while the slow call is still parked.
    for _ in 0..<200 where sink.response(id: 2) == nil {
        try? await Task.sleep(nanoseconds: 10_000_000)
        server.flush()
    }
    #expect(sink.response(id: 2) != nil)
    #expect(sink.response(id: 3) != nil)
    #expect(sink.response(id: 1) == nil)

    server.handle(line: line(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 1]]))
    await server.waitUntilIdle()
    server.flush()
    #expect(sink.response(id: 1) == nil)
}

@Test func stringAndNumberIdsAreDistinct() async {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": "1", "method": "tools/call", "params": ["name": "echo"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "echo"]]))
    await server.waitUntilIdle()
    server.flush()
    #expect(sink.response(id: "1") != nil)
    #expect(sink.response(id: 1) != nil)
}

@Test func heartbeatSendsProgressWhileWaiting() async {
    let gate = Gate()
    let waiting = MCPTool(name: "wait", description: "wait", inputSchema: ["type": "object"],
                          heartbeatInterval: 0.05) { _, _ in
        await gate.wait()
        return .structured([:])
    }
    let (server, sink) = makeServer(tools: [waiting])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "tools/call",
                              "params": ["name": "wait", "_meta": ["progressToken": "tok"]]]))
    try? await Task.sleep(nanoseconds: 300_000_000)
    await gate.open()
    await server.waitUntilIdle()
    server.flush()
    let progress = sink.messages.filter { $0["method"] == "notifications/progress" }
    #expect(progress.count >= 2)
    #expect(progress.allSatisfy { $0["params"]?["progressToken"] == "tok" })
    let values = progress.compactMap { $0["params"]?["progress"]?.double }
    #expect(values == values.sorted() && Set(values).count == values.count)
    #expect(sink.response(id: 1) != nil)
}

@Test func jsonValueRoundTripsNumbersAndBooleans() throws {
    let text = #"{"i":3,"d":2.5,"b":true,"n":null,"s":"x","a":[1,false]}"#
    let value = JSONValue(any: try JSONSerialization.jsonObject(with: Data(text.utf8)))
    #expect(value["i"] == .int(3))
    #expect(value["d"] == .double(2.5))
    #expect(value["b"] == .bool(true))
    #expect(value["n"] == .null)
    #expect(value["a"] == [1, false])
}

// MARK: - Modern era (2026-07-28)

private func modernMeta(client: String = "modern-client", version: String = "2026-07-28") -> JSONValue {
    ["io.modelcontextprotocol/protocolVersion": .string(version),
     "io.modelcontextprotocol/clientInfo": ["name": .string(client), "version": "1"],
     "io.modelcontextprotocol/clientCapabilities": [:]]
}

@Test func discoverAdvertisesVersionsCapabilitiesAndIdentity() {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": "d", "method": "server/discover", "params": ["_meta": modernMeta()]]))
    server.flush()
    let result = sink.response(id: "d")?["result"]
    #expect(result?["resultType"] == "complete")
    #expect(result?["supportedVersions"] == .array(MCPServer.supportedProtocolVersions.map(JSONValue.string)))
    #expect(result?["capabilities"]?["tools"] == [:])
    #expect(result?["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"] == "test")
    #expect(result?["ttlMs"]?.double != nil && result?["cacheScope"] == "public")
}

@Test func modernRequestsNeedNoHandshake() async {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": ["_meta": modernMeta()]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                              "params": ["name": "echo", "arguments": ["a": 1], "_meta": modernMeta(client: "per-request")]]))
    await server.waitUntilIdle()
    server.flush()
    let list = sink.response(id: 1)?["result"]
    #expect(list?["resultType"] == "complete" && list?["cacheScope"] == "public")
    #expect(list?["tools"]?.array?.first?["outputSchema"] != nil)
    let call = sink.response(id: 2)?["result"]
    #expect(call?["resultType"] == "complete")
    #expect(call?["ttlMs"] == nil)  // tool results are not cacheable
    // The client named in the request's _meta reaches the tool.
    #expect(call?["structuredContent"]?["client"] == "per-request")
}

@Test func unsupportedVersionIsRejectedWithTheSupportedList() {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": ["_meta": modernMeta(version: "1900-01-01")]]))
    server.flush()
    let error = sink.response(id: 1)?["error"]
    #expect(error?["code"] == -32022)
    #expect(error?["data"]?["requested"] == "1900-01-01")
    #expect(error?["data"]?["supported"] == .array(MCPServer.supportedProtocolVersions.map(JSONValue.string)))
}

@Test func malformedModernRequestsAreInvalidParams() async {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": 0, "method": "initialize",
                              "params": ["protocolVersion": "2025-11-25", "clientInfo": ["name": "handshake-client"]]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "tools/list",
                              "params": ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28"]]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "tools/list",
                              "params": ["_meta": ["io.modelcontextprotocol/protocolVersion": 20260728,
                                                   "io.modelcontextprotocol/clientCapabilities": [:]]]]))
    // A modern request without clientInfo does not inherit the handshake's client.
    server.handle(line: line(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                              "params": ["name": "echo", "arguments": [:],
                                         "_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28",
                                                   "io.modelcontextprotocol/clientCapabilities": [:]]]]))
    await server.waitUntilIdle()
    server.flush()
    #expect(sink.response(id: 1)?["error"]?["code"] == -32602)
    #expect(sink.response(id: 2)?["error"]?["code"] == -32602)
    #expect(sink.response(id: 3)?["result"]?["structuredContent"]?["client"] == .null)
}

@Test func legacyResultsStayUnchanged() async {
    let (server, sink) = makeServer(tools: [echoTool])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 3, "method": "initialize", "params": ["protocolVersion": "2026-07-28"]]))
    await server.waitUntilIdle()
    server.flush()
    let list = sink.response(id: 2)?["result"]
    #expect(list?["resultType"] == nil && list?["ttlMs"] == nil && list?["_meta"] == nil)
    // initialize only negotiates handshake revisions.
    #expect(sink.response(id: 3)?["result"]?["protocolVersion"] == .string(MCPServer.legacyProtocolVersions[0]))
}
