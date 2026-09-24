// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// MCPStdio.swift - a small MCP (Model Context Protocol) server core: JSON-RPC 2.0 over
// newline-delimited stdio, tools only. Foundation only and no host-specific code, so the file can
// be copied into another server as is.
//
// Shape (after replay's concurrent dispatcher, in Swift concurrency):
// - one background thread reads stdin a line at a time;
// - each tools/call runs as its own Task, so a tool that waits for a person does not stop the
//   server from answering ping, tools/list or other calls; responses may complete out of order,
//   which JSON-RPC allows;
// - one serial queue owns the output, so messages never interleave;
// - notifications/cancelled cancels the named call's Task and suppresses its response;
// - a tool may ask for a heartbeat: while it runs, notifications/progress goes out at an interval
//   when the request carried a progress token, which keeps clients with an idle timeout waiting.
//
// Both protocol eras, as a "dual-era" server:
// - legacy (2025-11-25 and older): an `initialize` handshake fixes the revision for the process.
//   Negotiation is tolerant like pdfutil's: an unknown or missing version gets the newest legacy one.
// - modern (2026-07-28): no handshake. Each request names its revision, client capabilities and
//   client identity in `_meta`; `server/discover` advertises the supported revisions; results carry
//   `resultType` and the server's identity; list results carry cache hints. A request naming a
//   revision we do not speak gets UnsupportedProtocolVersionError (-32022) with the list.
// A request without `_meta` is served under the revision `initialize` negotiated. structuredContent
// and outputSchema are sent only to revisions that have them.

import Foundation

// MARK: - JSONValue

/// A JSON value that can cross concurrency domains. Built from and turned back into the
/// Foundation objects JSONSerialization uses; integers and doubles stay distinct, so an id or a
/// count echoes back exactly as it came in.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Converts a JSONSerialization result. Anything that is not JSON becomes null.
    public init(any value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { JSONValue(any: $0) })
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    /// The Foundation form, for JSONSerialization.
    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map { $0.any }
        case .object(let value): return value.mapValues { $0.any }
        }
    }

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// A number as Double, whether it was written as an integer or not.
    public var double: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        object?[key]
    }

    /// Compact serialization with sorted keys, so output is deterministic.
    public func serialized() -> String {
        // Top-level fragments (a bare string or number) need .fragmentsAllowed.
        guard let data = try? JSONSerialization.data(withJSONObject: any,
                                                     options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
                     ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Tools

/// What a tool handler returns. Failures the agent should see and act on are results with
/// `isError: true`, never JSON-RPC errors (MCP's convention for tool execution errors).
public struct MCPToolResult: Sendable {
    public var content: [JSONValue]
    public var structuredContent: JSONValue?
    public var isError: Bool

    public init(content: [JSONValue], structuredContent: JSONValue? = nil, isError: Bool = false) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }

    /// A structured result. The same object also goes out serialized in a text block, as the
    /// specification recommends, for clients that ignore structured content.
    public static func structured(_ value: JSONValue) -> MCPToolResult {
        MCPToolResult(content: [["type": "text", "text": .string(value.serialized())]], structuredContent: value)
    }

    public static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(content: [["type": "text", "text": .string(message)]], isError: true)
    }
}

/// Per-call information handed to a tool handler.
public struct MCPToolContext: Sendable {
    /// `clientInfo.name` from the handshake, when the client sent one.
    public let clientName: String?
    fileprivate let progressSink: (@Sendable (Double, Double?, String?) -> Void)?

    /// True when the request carried a progress token, so progress() reaches the client.
    public var canReportProgress: Bool { progressSink != nil }

    /// Sends notifications/progress for this call. `progress` must grow with every call.
    public func progress(_ progress: Double, total: Double? = nil, message: String? = nil) {
        progressSink?(progress, total, message)
    }
}

public struct MCPTool: Sendable {
    public typealias Handler = @Sendable (_ arguments: [String: JSONValue], _ context: MCPToolContext) async throws -> MCPToolResult

    public let name: String
    public let title: String?
    public let description: String
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue?
    public let annotations: JSONValue?
    /// When set, the server sends notifications/progress at this interval (seconds) while the
    /// call runs, provided the request carried a progress token. For tools that wait on a person.
    public let heartbeatInterval: Double?
    public let handler: Handler

    public init(name: String, title: String? = nil, description: String, inputSchema: JSONValue,
                outputSchema: JSONValue? = nil, annotations: JSONValue? = nil,
                heartbeatInterval: Double? = nil, handler: @escaping Handler) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.heartbeatInterval = heartbeatInterval
        self.handler = handler
    }
}

/// Thrown by a handler for bad arguments; becomes an `isError` result with this message.
public struct MCPToolError: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

// MARK: - Resources

/// A resource the server lists; its text is read on demand through `MCPResources.read`.
public struct MCPResource: Sendable {
    public let uri: String
    public let name: String
    public let title: String?
    public let description: String?
    public let mimeType: String?

    public init(uri: String, name: String, title: String? = nil, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
    }

    fileprivate var definition: JSONValue {
        var object: [String: JSONValue] = ["uri": .string(uri), "name": .string(name)]
        if let title { object["title"] = .string(title) }
        if let description { object["description"] = .string(description) }
        if let mimeType { object["mimeType"] = .string(mimeType) }
        return .object(object)
    }
}

/// A family of resources addressed by an RFC 6570 URI template, such as actionui://docs/elements/{type}.
public struct MCPResourceTemplate: Sendable {
    public let uriTemplate: String
    public let name: String
    public let description: String?
    public let mimeType: String?

    public init(uriTemplate: String, name: String, description: String? = nil, mimeType: String? = nil) {
        self.uriTemplate = uriTemplate
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }

    fileprivate var definition: JSONValue {
        var object: [String: JSONValue] = ["uriTemplate": .string(uriTemplate), "name": .string(name)]
        if let description { object["description"] = .string(description) }
        if let mimeType { object["mimeType"] = .string(mimeType) }
        return .object(object)
    }
}

/// Read-only text resources. `read` returns nil for a URI it does not know.
public struct MCPResources: Sendable {
    public let resources: [MCPResource]
    public let templates: [MCPResourceTemplate]
    public let read: @Sendable (_ uri: String) -> (mimeType: String, text: String)?

    public init(resources: [MCPResource], templates: [MCPResourceTemplate] = [],
                read: @escaping @Sendable (_ uri: String) -> (mimeType: String, text: String)?) {
        self.resources = resources
        self.templates = templates
        self.read = read
    }
}

// MARK: - Server

public final class MCPServer: @unchecked Sendable {
    /// Handshake-based revisions, newest first; element 0 answers an initialize asking for an
    /// unknown or missing version. 2025-03-26 is absent on purpose: it is the one revision that
    /// requires receiving JSON-RPC batches, and this server reads one object per line (same
    /// reasoning as pdfutil).
    public static let legacyProtocolVersions = ["2025-11-25", "2025-06-18", "2024-11-05"]
    /// Per-request revisions (no handshake), newest first.
    public static let modernProtocolVersions = ["2026-07-28"]
    public static let supportedProtocolVersions = modernProtocolVersions + legacyProtocolVersions
    /// First revision with structuredContent and outputSchema.
    private static let structuredContentVersion = "2025-06-18"
    /// Tools never change while the process runs; clients may cache the list this long.
    private static let listCacheMilliseconds = 3_600_000

    /// How one request is served: under which revision, and for which client.
    private struct Era {
        let version: String
        let clientName: String?
        var isModern: Bool { version >= MCPServer.modernProtocolVersions.last! }
        var hasStructuredContent: Bool { version >= MCPServer.structuredContentVersion }
    }

    private let name: String
    private let version: String
    private let instructions: String?
    private let tools: [MCPTool]
    private let toolsByName: [String: MCPTool]
    private let resources: MCPResources?
    private let output: @Sendable (Data) -> Void
    private let writeQueue = DispatchQueue(label: "MCPServer.output")

    // Guarded by `lock`.
    private let lock = NSLock()
    private var negotiatedVersion = MCPServer.legacyProtocolVersions[0]
    private var clientName: String?
    private var running: [String: Task<Void, Never>] = [:]
    private var cancelled: Set<String> = []

    /// - Parameter output: receives each complete message (JSON plus newline), always on one serial
    ///   queue. Use `reserveStandardOutput()` for the real stdout.
    public init(name: String, version: String, instructions: String? = nil, tools: [MCPTool],
                resources: MCPResources? = nil, output: @escaping @Sendable (Data) -> Void) {
        self.name = name
        self.version = version
        self.instructions = instructions
        self.tools = tools
        self.resources = resources
        self.toolsByName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.output = output
    }

    /// Moves the protocol channel off file descriptor 1 so nothing else in the process can corrupt
    /// it: descriptor 1 is duplicated to a private descriptor that only the returned writer uses,
    /// then descriptor 1 is pointed at stderr, so a stray print() from any library lands in the log
    /// instead of in the middle of a JSON-RPC message. Call once, before anything can print.
    /// Also ignores SIGPIPE, so a client that has gone away cannot kill the process mid-write.
    public static func reserveStandardOutput() -> @Sendable (Data) -> Void {
        signal(SIGPIPE, SIG_IGN)
        fflush(stdout)
        let protocolFD = dup(STDOUT_FILENO)
        guard protocolFD >= 0 else {
            FileHandle.standardError.write(Data("MCPServer: dup(stdout) failed (errno \(errno)); writing to stdout directly\n".utf8))
            return { data in writeAll(data, to: STDOUT_FILENO) }
        }
        // A child process (such as a future re-hosted viewer) must not inherit the protocol channel.
        _ = fcntl(protocolFD, F_SETFD, FD_CLOEXEC)
        if dup2(STDERR_FILENO, STDOUT_FILENO) < 0 {
            FileHandle.standardError.write(Data("MCPServer: dup2(stderr, stdout) failed (errno \(errno)); stray output may corrupt the protocol\n".utf8))
        }
        return { data in writeAll(data, to: protocolFD) }
    }

    private static func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return  // EPIPE and friends: the client is gone; nothing useful to do.
                }
                pointer += written
                remaining -= written
            }
        }
    }

    /// Starts the stdin reader on a background thread. `onEndOfInput` runs on that thread after
    /// stdin closes, which is how a stdio client ends the session.
    public func startReading(onEndOfInput: @escaping @Sendable () -> Void) {
        let thread = Thread { [self] in
            while let line = readLine(strippingNewline: true) {
                handle(line: line)
            }
            onEndOfInput()
        }
        thread.name = "MCPServer.reader"
        thread.start()
    }

    /// Cancels every running tool call; their responses are not sent.
    public func cancelAll() {
        lock.lock()
        let tasks = running
        cancelled.formUnion(tasks.keys)
        lock.unlock()
        for task in tasks.values { task.cancel() }
    }

    /// Waits until no tool call is running. For tests.
    public func waitUntilIdle() async {
        while true {
            let tasks = lock.withLock { Array(running.values) }
            if tasks.isEmpty { return }
            for task in tasks { await task.value }
        }
    }

    /// Returns once every message sent so far has been handed to `output`. For tests.
    public func flush() {
        writeQueue.sync {}
    }

    /// Handles one line of input. Public so tests can drive the server without a pipe.
    public func handle(line: String) {
        if line.allSatisfy({ $0.isWhitespace }) { return }
        guard let data = line.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            send(errorResponse(id: .null, code: -32700, message: "parse error"))
            return
        }
        guard case .object(let message) = JSONValue(any: parsed) else {
            send(errorResponse(id: .null, code: -32600, message: "invalid request"))
            return
        }
        // A message with no "id" member is a notification: never answered.
        let id = message["id"]
        guard let method = message["method"]?.string else {
            if let id { send(errorResponse(id: id, code: -32600, message: "invalid request")) }
            return
        }
        let params = message["params"]?.object ?? [:]

        guard let id else {
            if method == "notifications/cancelled", let requestID = params["requestId"] {
                cancel(requestID: requestID)
            }
            return  // notifications/initialized and anything else: nothing to do.
        }

        if method == "initialize" {
            send(resultResponse(id: id, result: initialize(params: params)))
            return
        }
        guard let era = era(of: params, id: id) else { return }
        switch method {
        case "server/discover":
            // A modern-only method: always the modern result shape, even for a request that named
            // no revision.
            let shape = era.isModern ? era : Era(version: Self.modernProtocolVersions[0], clientName: nil)
            send(resultResponse(id: id, result: complete(discover(), era: shape, cacheable: true)))
        case "ping":  // legacy only; harmless to answer in either era
            send(resultResponse(id: id, result: complete([:], era: era)))
        case "tools/list":
            send(resultResponse(id: id, result: complete(["tools": .array(toolDefinitions(era: era))], era: era, cacheable: true)))
        case "tools/call":
            call(id: id, params: params, era: era)
        case "resources/list" where resources != nil:
            let list = resources!.resources.map(\.definition)
            send(resultResponse(id: id, result: complete(["resources": .array(list)], era: era, cacheable: true)))
        case "resources/templates/list" where resources != nil:
            let list = resources!.templates.map(\.definition)
            send(resultResponse(id: id, result: complete(["resourceTemplates": .array(list)], era: era, cacheable: true)))
        case "resources/read" where resources != nil:
            readResource(id: id, params: params, era: era)
        default:
            send(errorResponse(id: id, code: -32601, message: "method not found: \(method)"))
        }
    }

    /// The revision and client a request is served for: its own `_meta` when it names a revision
    /// (modern requests), else what `initialize` negotiated. Sends UnsupportedProtocolVersionError
    /// and returns nil for a revision we do not speak.
    private func era(of params: [String: JSONValue], id: JSONValue) -> Era? {
        let meta = params["_meta"]?.object ?? [:]
        lock.lock()
        let negotiated = negotiatedVersion
        let handshakeClient = clientName
        lock.unlock()
        let requestClient = meta["io.modelcontextprotocol/clientInfo"]?["name"]?.string
        guard let requested = meta["io.modelcontextprotocol/protocolVersion"] else {
            return Era(version: negotiated, clientName: requestClient ?? handshakeClient)
        }
        guard let version = requested.string else {
            send(errorResponse(id: id, code: -32602, message: "io.modelcontextprotocol/protocolVersion must be a string"))
            return nil
        }
        guard Self.supportedProtocolVersions.contains(version) else {
            send(["jsonrpc": "2.0", "id": id, "error": [
                "code": -32022, "message": "Unsupported protocol version",
                "data": ["supported": .array(Self.supportedProtocolVersions.map(JSONValue.string)), "requested": requested],
            ]])
            return nil
        }
        let era = Era(version: version, clientName: requestClient ?? handshakeClient)
        guard era.isModern else { return era }
        // A modern request missing a required field is malformed (-32602), and it must not borrow
        // anything, such as the client's identity, from an earlier initialize.
        guard meta["io.modelcontextprotocol/clientCapabilities"]?.object != nil else {
            send(errorResponse(id: id, code: -32602, message: "missing io.modelcontextprotocol/clientCapabilities in _meta"))
            return nil
        }
        return Era(version: version, clientName: requestClient)
    }

    /// Adds what a modern result carries: resultType, the server's identity, and for cacheable
    /// results the cache hints. Legacy results are returned unchanged.
    private func complete(_ result: JSONValue, era: Era, cacheable: Bool = false) -> JSONValue {
        guard era.isModern, case .object(var object) = result else { return result }
        object["resultType"] = "complete"
        var meta = object["_meta"]?.object ?? [:]
        meta["io.modelcontextprotocol/serverInfo"] = ["name": .string(name), "version": .string(version)]
        object["_meta"] = .object(meta)
        if cacheable {
            object["ttlMs"] = .int(Self.listCacheMilliseconds)
            object["cacheScope"] = "public"
        }
        return .object(object)
    }

    // MARK: Methods

    private func initialize(params: [String: JSONValue]) -> JSONValue {
        // Only handshake revisions are negotiated here; a modern client does not send initialize.
        let requested = params["protocolVersion"]?.string
        let version = requested.flatMap { Self.legacyProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.legacyProtocolVersions[0]
        lock.lock()
        negotiatedVersion = version
        clientName = params["clientInfo"]?["name"]?.string
        lock.unlock()
        var result: [String: JSONValue] = [
            "protocolVersion": .string(version),
            "capabilities": capabilities,
            "serverInfo": ["name": .string(name), "version": .string(self.version)],
        ]
        if let instructions { result["instructions"] = .string(instructions) }
        return .object(result)
    }

    /// Tools always; resources when the server was given some.
    private var capabilities: JSONValue {
        resources == nil ? ["tools": [:]] : ["tools": [:], "resources": [:]]
    }

    private func readResource(id: JSONValue, params: [String: JSONValue], era: Era) {
        guard let uri = params["uri"]?.string else {
            send(errorResponse(id: id, code: -32602, message: "missing uri"))
            return
        }
        guard let found = resources?.read(uri) else {
            // 2026-07-28 moved "resource not found" from -32002 to -32602 (invalid params).
            send(["jsonrpc": "2.0", "id": id, "error": [
                "code": .int(era.isModern ? -32602 : -32002), "message": "Resource not found", "data": ["uri": .string(uri)],
            ]])
            return
        }
        let contents: JSONValue = ["uri": .string(uri), "mimeType": .string(found.mimeType), "text": .string(found.text)]
        send(resultResponse(id: id, result: complete(["contents": [contents]], era: era, cacheable: true)))
    }

    private func discover() -> JSONValue {
        var result: [String: JSONValue] = [
            "supportedVersions": .array(Self.supportedProtocolVersions.map(JSONValue.string)),
            "capabilities": capabilities,
        ]
        if let instructions { result["instructions"] = .string(instructions) }
        return .object(result)
    }

    // Revisions are ISO dates, so string order is date order.
    private func toolDefinitions(era: Era) -> [JSONValue] {
        let structured = era.hasStructuredContent
        return tools.map { tool in
            var definition: [String: JSONValue] = [
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema,
            ]
            if structured {
                if let title = tool.title { definition["title"] = .string(title) }
                if let outputSchema = tool.outputSchema { definition["outputSchema"] = outputSchema }
            }
            if let annotations = tool.annotations { definition["annotations"] = annotations }
            return .object(definition)
        }
    }

    private func call(id: JSONValue, params: [String: JSONValue], era: Era) {
        guard let toolName = params["name"]?.string else {
            send(errorResponse(id: id, code: -32602, message: "missing tool name"))
            return
        }
        guard let tool = toolsByName[toolName] else {
            send(errorResponse(id: id, code: -32602, message: "unknown tool: \(toolName)"))
            return
        }
        let arguments = params["arguments"]?.object ?? [:]
        let key = Self.key(for: id)

        lock.lock()
        let context = MCPToolContext(clientName: era.clientName,
                                     progressSink: progressSink(token: params["_meta"]?["progressToken"]))
        if running[key] != nil {
            lock.unlock()
            send(errorResponse(id: id, code: -32600, message: "request id already in use"))
            return
        }
        // Registered under the lock, so the task's own completion (which takes the lock) always
        // finds its entry.
        running[key] = Task { [self] in
            let heartbeat = startHeartbeat(tool: tool, context: context)
            let result: MCPToolResult
            do {
                result = try await tool.handler(arguments, context)
            } catch let error as MCPToolError {
                result = .error(error.message)
            } catch is CancellationError {
                result = .error("cancelled")
            } catch {
                result = .error(error.localizedDescription)
            }
            // Cancel and then wait for the heartbeat, so a beat that is already past its
            // cancellation check cannot go out after the response.
            if let heartbeat {
                heartbeat.cancel()
                await heartbeat.value
            }
            finish(id: id, key: key, result: result, era: era)
        }
        lock.unlock()
    }

    private func finish(id: JSONValue, key: String, result: MCPToolResult, era: Era) {
        lock.lock()
        running[key] = nil
        let wasCancelled = cancelled.remove(key) != nil
        lock.unlock()
        // The specification asks receivers of notifications/cancelled not to answer the request.
        guard !wasCancelled else { return }
        var body: [String: JSONValue] = ["content": .array(result.content)]
        if let structured = result.structuredContent, era.hasStructuredContent {
            body["structuredContent"] = structured
        }
        if result.isError { body["isError"] = true }
        send(resultResponse(id: id, result: complete(.object(body), era: era)))
    }

    private func cancel(requestID: JSONValue) {
        let key = Self.key(for: requestID)
        lock.lock()
        let task = running[key]
        if task != nil { cancelled.insert(key) }
        lock.unlock()
        task?.cancel()
    }

    private func progressSink(token: JSONValue?) -> (@Sendable (Double, Double?, String?) -> Void)? {
        guard let token, token != .null else { return nil }
        return { [self] progress, total, message in
            var params: [String: JSONValue] = ["progressToken": token, "progress": .double(progress)]
            if let total { params["total"] = .double(total) }
            if let message { params["message"] = .string(message) }
            send(["jsonrpc": "2.0", "method": "notifications/progress", "params": .object(params)])
        }
    }

    private func startHeartbeat(tool: MCPTool, context: MCPToolContext) -> Task<Void, Never>? {
        guard let interval = tool.heartbeatInterval, interval > 0, context.canReportProgress else { return nil }
        return Task {
            var beats = 0.0
            while true {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                beats += 1
                context.progress(beats * interval, message: "waiting for the user")
            }
        }
    }

    // MARK: Output

    /// Request ids are strings or integers; the key keeps "1" and 1 apart.
    private static func key(for id: JSONValue) -> String {
        switch id {
        case .string(let value): return "s:" + value
        default: return "v:" + id.serialized()
        }
    }

    private func resultResponse(id: JSONValue, result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]
    }

    private func send(_ message: JSONValue) {
        let line = Data((message.serialized() + "\n").utf8)
        writeQueue.async { [output] in output(line) }
    }
}
