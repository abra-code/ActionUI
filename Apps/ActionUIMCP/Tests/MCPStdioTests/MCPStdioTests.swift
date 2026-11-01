// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if os(Linux)
import ActionUI
import Glibc
#endif
import Testing
@testable import MCPStdio

/// What a host passes the server to parse JSON text, on each platform.
private let parseJSON: @Sendable (String) -> JSONValue? = { text in
    #if os(Linux)
    return (try? ActionUIJSON.value(from: text)).map { JSONValue(any: $0) }
    #else
    return JSONValue.parsedByFoundation(text)
    #endif
}

/// Collects the server's output lines.
private final class Sink: @unchecked Sendable {
    private let lock = MCPLock()
    private var lines: [JSONValue] = []

    func append(_ data: Data) {
        let value = parseJSON(String(decoding: data, as: UTF8.self)) ?? .null
        lock.withLock { lines.append(value) }
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
    let server = MCPServer(name: "test", version: "1", tools: tools, parse: parseJSON, output: { sink.append($0) })
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
    let value = try #require(parseJSON(text))
    #expect(value["i"] == .int(3))
    #expect(value["d"] == .double(2.5))
    #expect(value["b"] == .bool(true))
    #expect(value["n"] == .null)
    #expect(value["a"] == [1, false])
    // Through the native form and back, null included.
    #expect(JSONValue(any: value.any) == value)
}

@Test func otherNumberTypesKeepTheirValue() {
    #expect(JSONValue(any: Float(0.5)) == .double(0.5))
    #expect(JSONValue(any: Int64(7)) == .int(7))
    #expect(JSONValue(any: UInt8(3)) == .int(3))
}

@Test func readerHandsOverLinesHoweverTheyArrive() async throws {
    var ends: [Int32] = [0, 0]
    #expect(pipe(&ends) == 0)
    let (reader, writer) = (ends[0], ends[1])
    let (server, sink) = makeServer(tools: [echoTool])
    let finished = Gate()
    server.startReading(from: reader) { Task { await finished.open() } }
    func send(_ text: String) {
        var bytes = Array(text.utf8)[...]
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { write(writer, $0.baseAddress, $0.count) }
            #expect(written > 0)
            guard written > 0 else { return }
            bytes = bytes.dropFirst(written)
        }
    }
    let ping = { (id: Int) in line(["jsonrpc": "2.0", "id": .int(id), "method": "ping"]) }
    // Two lines at once, and a blank one, which is no message.
    send(ping(1) + "\n\n" + ping(2) + "\n")
    // One line in two pieces, ended with CR and LF.
    let third = ping(3)
    send(String(third.prefix(10)))
    try await Task.sleep(nanoseconds: 20_000_000)
    send(String(third.dropFirst(10)) + "\r\n")
    // A line longer than one read.
    let long = String(repeating: "x", count: 200_000)
    send(line(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "echo", "arguments": ["text": .string(long)]]]) + "\n")
    // A last line with no newline.
    send(ping(5))
    close(writer)
    await finished.wait()
    close(reader)
    await server.waitUntilIdle()
    server.flush()
    #expect(sink.messages.count == 5)
    for id in [1, 2, 3, 5] {
        #expect(sink.response(id: .int(id))?["result"] == [:])
    }
    #expect(sink.response(id: 4)?["result"]?["structuredContent"]?["arguments"]?["text"] == .string(long))
}

@Test func serializedWritesCompactJSONWithSortedKeys() {
    let value: JSONValue = ["b": [1, 2.5, -0.25, 1e-07, 3.0, true, nil], "a": "x/y", "c": [:], "d": []]
    #expect(value.serialized() == #"{"a":"x/y","b":[1,2.5,-0.25,1e-07,3,true,null],"c":{},"d":[]}"#)
}

@Test func serializedEscapesStrings() {
    let text = "quote \" back \\ tab \t line \n return \r feed \u{0C} bell \u{08} low \u{01} high \u{1F} del \u{7F} e\u{301} \u{1F600}"
    let written = JSONValue.string(text).serialized()
    #expect(written == #""quote \" back \\ tab \t line \n return \r feed \f bell \b low \u0001 high \u001f del "# + "\u{7F} e\u{301} \u{1F600}\"")
    #expect(parseJSON("[" + written + "]")?.array?.first == .string(text))
}

@Test func serializedWritesNoNumberJSONCannotHold() {
    #expect(JSONValue.array([.double(.nan), .double(.infinity), .double(-.infinity), 1]).serialized() == "[null,null,null,1]")
}

@Test func serializedFragments() {
    #expect(JSONValue.null.serialized() == "null")
    #expect(JSONValue.int(-7).serialized() == "-7")
    #expect(JSONValue.string("").serialized() == "\"\"")
}

#if !os(Linux)
/// The text JSONSerialization wrote before JSONValue wrote its own.
@Test func serializedMatchesJSONSerialization() throws {
    let values: [JSONValue] = [
        ["jsonrpc": "2.0", "id": 1, "result": ["content": [["type": "text", "text": "a/b \"c\"\n\u{1F600}\u{7F}\u{01}"]], "isError": false]],
        [2.5, 3.0, -1.5, 100, 1234567.25, 0, -0.5, -0.0, 1e21],
        ["empty": [:], "list": [], "null": nil, "yes": true, "no": false],
    ]
    for value in values {
        let data = try JSONSerialization.data(withJSONObject: value.any, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        #expect(value.serialized() == String(decoding: data, as: UTF8.self))
    }
}

/// JSONSerialization writes 17 digits (0.1 as 0.10000000000000001), JSONValue the shortest text
/// that reads back as the same number.
@Test func serializedDoublesReadBackExactly() throws {
    let numbers = [0.1, 0.30000000000000004, 1e-07, 1e16, 1.5e300, 5e-324, 1.2345678901234568e+17]
    let text = JSONValue.array(numbers.map(JSONValue.double)).serialized()
    #expect(text.hasPrefix("[0.1,0.30000000000000004,1e-07,"))
    let parsed = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Double])
    #expect(parsed == numbers)
}
#endif

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

// MARK: - Resources

private let docs = MCPResources(
    resources: [MCPResource(uri: "test://a", name: "a", mimeType: "text/plain")],
    templates: [MCPResourceTemplate(uriTemplate: "test://{x}", name: "x")]
) { uri in uri == "test://a" ? ("text/plain", "hello") : nil }

@Test func resourcesAreListedAndRead() {
    let sink = Sink()
    let server = MCPServer(name: "test", version: "1", tools: [], resources: docs, parse: parseJSON, output: { sink.append($0) })
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "resources/list"]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 3, "method": "resources/templates/list"]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 4, "method": "resources/read", "params": ["uri": "test://a"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 5, "method": "resources/read", "params": ["uri": "test://b"]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 6, "method": "resources/read",
                              "params": ["uri": "test://b", "_meta": modernMeta()]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 7, "method": "resources/read",
                              "params": ["uri": "test://a", "_meta": modernMeta()]]))
    server.flush()
    #expect(sink.response(id: 1)?["result"]?["capabilities"]?["resources"] == [:])
    #expect(sink.response(id: 2)?["result"]?["resources"]?.array?.first?["uri"] == "test://a")
    #expect(sink.response(id: 3)?["result"]?["resourceTemplates"]?.array?.first?["uriTemplate"] == "test://{x}")
    #expect(sink.response(id: 4)?["result"]?["contents"] == [["uri": "test://a", "mimeType": "text/plain", "text": "hello"]])
    // Not found: -32002 in the legacy revisions, -32602 from 2026-07-28 on.
    #expect(sink.response(id: 5)?["error"]?["code"] == -32002)
    #expect(sink.response(id: 6)?["error"]?["code"] == -32602)
    // A modern read is cacheable.
    #expect(sink.response(id: 7)?["result"]?["cacheScope"] == "public")
}

@Test func noResourcesMeansNoCapabilityAndNoMethods() {
    let (server, sink) = makeServer(tools: [])
    server.handle(line: line(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:]]))
    server.handle(line: line(["jsonrpc": "2.0", "id": 2, "method": "resources/list"]))
    server.flush()
    #expect(sink.response(id: 1)?["result"]?["capabilities"]?["resources"] == nil)
    #expect(sink.response(id: 2)?["error"]?["code"] == -32601)
}
