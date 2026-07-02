// Add-ons/ActionUIChat/Sources/ACP/ACPChatTransport.swift
//
// The ACP (Agent Client Protocol) transport: launches an ACP agent as a subprocess
// (over ACPConnection's stdio JSON-RPC) and maps the ACP session vocabulary onto the
// normalized ChatEvent / ChatCommand stream. This file is the ONLY place that knows
// ACP's method names and payload shapes (the design doc's "keep the transport's ACP
// mapping in one file"); everything above it - store, router, views - is unchanged
// from the scripted local transport.
//
// Lifecycle: start() launches the agent, runs `initialize` (advertising NO fs /
// terminal capabilities - this host is a chat surface, not an editor, so the agent
// must not assume one), opens a session with `session/new` (cwd + declared MCP
// servers), and emits sessionReady. A `.prompt` command becomes one `session/prompt`
// turn; during the turn the agent streams `session/update` notifications which demux
// onto ChatEvents per the design doc's table, and the turn ends when the prompt
// request resolves with a stopReason. `.cancel` sends the `session/cancel`
// notification (the in-flight prompt then resolves with stopReason "cancelled").
// `session/request_permission` parks the agent's request on a continuation until the
// UI answers via `.permissionResponse` (or the turn is cancelled), then resolves with
// ACP's selected / cancelled outcome. fs/* and terminal/* requests are answered
// "method not found" since the capabilities were never advertised.
//
// Message identity: ACP does not carry per-message IDs - chunks belong to the turn.
// The transport owns the segmentation: contiguous runs of agent_message_chunk /
// user_message_chunk / agent_thought_chunk become one transcript item each; a run
// closes when a different update kind (or the turn's end) arrives. A mid-turn segment
// close emits messageEnd with a nil stopReason (the turn continues); the final close
// carries the prompt's real stopReason.
//
// macOS-only, like ACPConnection (subprocesses do not exist on iOS); the factory
// falls back to the local transport elsewhere. `@unchecked Sendable`: the mutable
// segmentation / permission state is guarded by `lock`.

#if os(macOS)

import Foundation
import ActionUI

final class ACPChatTransport: ChatTransport, @unchecked Sendable {

    let events: AsyncStream<ChatEvent>
    private let eventSink: AsyncStream<ChatEvent>.Continuation
    private let logger: any ActionUILogger

    private let command: [String]
    private let cwd: String
    private let mcpServers: [[String: Any]]

    private let lock = NSLock()
    private var connection: ACPConnection?
    private var sessionID: String?
    private var promptTask: Task<Void, Never>?

    // Segmentation state (see the header): the currently-open transcript items.
    private var itemCounter = 0
    private var openMessageID: String?
    private var openMessageRole: ChatRole = .agent
    private var openThoughtID: String?

    // Permission state: synthesized request ID -> the continuation parking the agent's
    // session/request_permission until the UI answers.
    private var permissionCounter = 0
    private var pendingPermissions: [String: CheckedContinuation<String?, Never>] = [:]

    /// `transport` config: `command` (argv array, required), `cwd` (string, defaults to
    /// the host's current directory), `mcpServers` (array of ACP server declarations,
    /// passed through verbatim).
    init(config: [String: Any], logger: any ActionUILogger) throws {
        guard let command = config["command"] as? [String], !command.isEmpty else {
            throw ACPConnectionError(code: nil, message: "transport.command (a non-empty string array) is required for protocol \"acp\"")
        }
        self.command = command
        // ACP requires the session cwd to be an ABSOLUTE path: agents resolve a relative
        // path against their own working directory (a literal "~" reached OpenCode as
        // "<cwd>/~" and failed session/new with "Invalid path"). Expand ~ and anchor
        // relative paths once here, so the launch and the wire see the same absolute path.
        self.cwd = Self.absoluteCwd(config["cwd"] as? String)
        self.mcpServers = (config["mcpServers"] as? [[String: Any]]) ?? []
        self.logger = logger
        var captured: AsyncStream<ChatEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        self.eventSink = captured
    }

    /// The configured cwd as the absolute path ACP requires: "~" expands, a relative
    /// path anchors to the host's current directory, nil/empty falls back to the
    /// host's current directory. Internal for tests.
    static func absoluteCwd(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return FileManager.default.currentDirectoryPath
        }
        let expanded = (raw as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return expanded
        }
        return URL(fileURLWithPath: expanded).path
    }

    // MARK: - ChatTransport

    func start() async {
        let connection = ACPConnection(
            logger: logger,
            onNotification: { [weak self] method, params in
                self?.handleNotification(method, params)
            },
            onRequest: { [weak self] method, params in
                await self?.handleRequest(method, params)
            },
            onClose: { [weak self] exitStatus in
                self?.handleAgentClosed(exitStatus: exitStatus)
            }
        )
        lock.withLock { self.connection = connection }

        do {
            try connection.launch(command: command, cwd: cwd)
            let initResult = try await connection.request("initialize", [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": ["readTextFile": false, "writeTextFile": false],
                    "terminal": false,
                ],
                // All three clientInfo fields: some agents (opencode) require `version`
                // to be present as a string when clientInfo is given at all.
                "clientInfo": ["name": "ActionUIChat", "title": "ActionUI Chat", "version": "1.0"],
            ])
            if let version = (initResult["protocolVersion"] as? NSNumber)?.intValue, version != 1 {
                logger.log("ACP: agent negotiated protocol version \(version) (client speaks 1); continuing", .warning)
            }
            let authMethods = (initResult["authMethods"] as? [[String: Any]]) ?? []

            do {
                let session = try await connection.request("session/new", [
                    "cwd": cwd,
                    "mcpServers": mcpServers,
                ])
                guard let sessionID = session["sessionId"] as? String else {
                    throw ACPConnectionError(code: nil, message: "session/new returned no sessionId")
                }
                lock.withLock { self.sessionID = sessionID }
                eventSink.yield(.sessionReady(sessionID: sessionID))
            } catch {
                // A common session/new failure is an agent that requires auth first; name
                // the advertised methods so that case is actionable (auth UX is a later
                // milestone) - but phrase it as a possibility, not a diagnosis: session/new
                // also fails for non-auth reasons (an agent-side internal error, say).
                if authMethods.isEmpty {
                    throw error
                }
                let names = authMethods.compactMap { $0["id"] as? String ?? $0["name"] as? String }
                throw ACPConnectionError(code: nil, message: "\(error). If the agent requires login, authenticate outside the chat element first (it advertises: \(names.joined(separator: ", ")))")
            }
        } catch {
            eventSink.yield(.error(message: "ACP agent failed to start: \(error)", recoverable: false))
            // No session, no retry path: do not leave the agent subprocess running
            // until the element's teardown gets around to it.
            connection.stop()
        }
    }

    func send(_ command: ChatCommand) async {
        switch command {
        case .prompt(let text):
            startTurn(prompt: text)

        case .cancel:
            let (connection, sessionID) = lock.withLock { (self.connection, self.sessionID) }
            guard let connection, let sessionID else {
                return
            }
            connection.notify("session/cancel", ["sessionId": sessionID])
            // Per ACP, a cancelled turn must also resolve any pending permission
            // requests with the cancelled outcome; the prompt then returns
            // stopReason "cancelled", which ends the turn.
            resolveAllPermissions(with: nil)

        case .permissionResponse(let requestID, let optionID):
            let continuation = lock.withLock { pendingPermissions.removeValue(forKey: requestID) }
            continuation?.resume(returning: optionID)
        }
    }

    func stop() async {
        let (connection, task) = lock.withLock { (self.connection, self.promptTask) }
        task?.cancel()
        resolveAllPermissions(with: nil)
        connection?.stop()
        eventSink.finish()
    }

    // MARK: - Outbound turn

    private func startTurn(prompt: String) {
        let (connection, sessionID) = lock.withLock { (self.connection, self.sessionID) }
        guard let connection, let sessionID else {
            eventSink.yield(.error(message: "ACP session is not ready; message not sent", recoverable: true))
            return
        }
        let task = Task { [weak self] in
            do {
                let result = try await connection.request("session/prompt", [
                    "sessionId": sessionID,
                    "prompt": [["type": "text", "text": prompt]],
                ])
                let stopReason = (result["stopReason"] as? String) ?? "end_turn"
                self?.finishTurn(stopReason: stopReason)
            } catch {
                self?.eventSink.yield(.error(message: "ACP turn failed: \(error)", recoverable: true))
                self?.finishTurn(stopReason: "error")
            }
        }
        lock.withLock { promptTask = task }
    }

    /// Ends the turn: closes whatever item is still open and emits the terminal
    /// messageEnd carrying the turn's real stopReason (a non-nil stopReason is what
    /// flips the store out of its streaming state).
    private func finishTurn(stopReason: String) {
        let itemID = lock.withLock { () -> String in
            openThoughtID = nil
            if let open = openMessageID {
                openMessageID = nil
                return open
            }
            itemCounter += 1
            return "acp-turn-\(itemCounter)"
        }
        eventSink.yield(.messageEnd(itemID: itemID, stopReason: stopReason))
    }

    // MARK: - Inbound: notifications (the session/update demux)

    // Internal (not private) so tests can drive the demux without a subprocess.
    func handleNotification(_ method: String, _ params: [String: Any]) {
        guard method == "session/update" else {
            logger.log("ACP: unhandled notification \(method)", .verbose)
            return
        }
        guard let update = params["update"] as? [String: Any],
              let kind = update["sessionUpdate"] as? String else {
            logger.log("ACP: session/update with no update payload; dropping", .warning)
            return
        }

        switch kind {
        case "agent_message_chunk":
            appendMessageChunk(update, role: .agent)

        case "user_message_chunk":
            appendMessageChunk(update, role: .local)

        case "agent_thought_chunk":
            let text = Self.contentText(update["content"])
            guard !text.isEmpty else {
                return
            }
            closeOpenMessage()
            let itemID = lock.withLock { () -> String in
                if let open = openThoughtID {
                    return open
                }
                itemCounter += 1
                let id = "acp-thought-\(itemCounter)"
                openThoughtID = id
                return id
            }
            eventSink.yield(.thoughtDelta(itemID: itemID, text: text))

        case "tool_call":
            closeOpenMessage()
            lock.withLock { openThoughtID = nil }
            eventSink.yield(.toolCall(Self.parseToolCall(update)))

        case "tool_call_update":
            eventSink.yield(.toolCallUpdate(Self.parseToolCallUpdate(update)))

        case "plan", "available_commands_update", "current_mode_update", "usage_update":
            // M5 surfaces (plan panel, slash-command menu, mode selector, usage line).
            logger.log("ACP: \(kind) received; surface arrives in a later milestone", .verbose)

        default:
            logger.log("ACP: unknown session update '\(kind)'; dropping", .verbose)
        }
    }

    /// Streams one message chunk into the open message segment for `role`, opening a
    /// new segment (messageStart) if none is open or the speaker changed.
    private func appendMessageChunk(_ update: [String: Any], role: ChatRole) {
        let text = Self.contentText(update["content"])
        guard !text.isEmpty else {
            return
        }
        lock.withLock { openThoughtID = nil }
        let (itemID, isNew) = lock.withLock { () -> (String, Bool) in
            if let open = openMessageID, openMessageRole == role {
                return (open, false)
            }
            itemCounter += 1
            let id = "acp-message-\(itemCounter)"
            return (id, true)
        }
        if isNew {
            closeOpenMessage()
            lock.withLock {
                openMessageID = itemID
                openMessageRole = role
            }
            eventSink.yield(.messageStart(itemID: itemID, role: role))
        }
        eventSink.yield(.messageDelta(itemID: itemID, text: text))
    }

    /// Closes the open message segment mid-turn (nil stopReason: the turn continues).
    private func closeOpenMessage() {
        let open = lock.withLock { () -> String? in
            let open = openMessageID
            openMessageID = nil
            return open
        }
        if let open {
            eventSink.yield(.messageEnd(itemID: open, stopReason: nil))
        }
    }

    // MARK: - Inbound: agent -> client requests

    // Internal (not private) so tests can drive the permission round-trip without a subprocess.
    // The result is `sending` (always freshly built here) so callers on other tasks can consume it.
    func handleRequest(_ method: String, _ params: [String: Any]) async -> sending [String: Any]? {
        guard method == "session/request_permission" else {
            // fs/* and terminal/* land here: the capabilities were not advertised, so a
            // conforming agent should not call them; answer method-not-found either way.
            logger.log("ACP: agent requested unsupported method \(method)", .verbose)
            return nil
        }

        let toolCall = params["toolCall"] as? [String: Any]
        let options = ((params["options"] as? [[String: Any]]) ?? []).compactMap { raw -> PermissionRequest.Option? in
            guard let id = raw["optionId"] as? String,
                  let kind = (raw["kind"] as? String).flatMap(PermissionRequest.Option.Kind.init(rawValue:)) else {
                return nil
            }
            return PermissionRequest.Option(id: id, name: (raw["name"] as? String) ?? id, kind: kind)
        }
        guard !options.isEmpty else {
            logger.log("ACP: permission request carried no usable options; answering cancelled", .warning)
            return ["outcome": ["outcome": "cancelled"]]
        }

        let requestID = lock.withLock { () -> String in
            permissionCounter += 1
            return "acp-permission-\(permissionCounter)"
        }
        let request = PermissionRequest(
            id: requestID,
            toolCallID: toolCall?["toolCallId"] as? String,
            title: (toolCall?["title"] as? String) ?? "Allow this tool call?",
            options: options
        )
        eventSink.yield(.permissionRequest(request))

        let chosen = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            lock.withLock { pendingPermissions[requestID] = continuation }
        }
        if let chosen {
            return ["outcome": ["outcome": "selected", "optionId": chosen]]
        }
        return ["outcome": ["outcome": "cancelled"]]
    }

    private func resolveAllPermissions(with optionID: String?) {
        let continuations = lock.withLock { () -> [CheckedContinuation<String?, Never>] in
            let waiting = Array(pendingPermissions.values)
            pendingPermissions.removeAll()
            return waiting
        }
        for continuation in continuations {
            continuation.resume(returning: optionID)
        }
    }

    private func handleAgentClosed(exitStatus: Int32?) {
        resolveAllPermissions(with: nil)
        let hadSession = lock.withLock { sessionID != nil }
        if hadSession {
            let status = exitStatus.map { " (exit status \($0))" } ?? ""
            eventSink.yield(.error(message: "The ACP agent exited\(status)", recoverable: false))
        }
    }

    // MARK: - Payload parsing (static, pure: unit-tested directly)

    /// Joins the text out of an ACP content value - either one ContentBlock or an array
    /// of them. Non-text blocks (image / audio / resource) are noted rather than lost.
    static func contentText(_ content: Any?) -> String {
        if let block = content as? [String: Any] {
            return textOfBlock(block)
        }
        if let blocks = content as? [[String: Any]] {
            return blocks.map(textOfBlock).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        return ""
    }

    private static func textOfBlock(_ block: [String: Any]) -> String {
        switch block["type"] as? String {
        case "text":
            return (block["text"] as? String) ?? ""
        case "resource_link":
            let name = (block["name"] as? String) ?? (block["uri"] as? String) ?? "resource"
            return "[\(name)]"
        case "resource":
            let resource = block["resource"] as? [String: Any]
            let uri = (resource?["uri"] as? String) ?? "resource"
            return "[\(uri)]"
        case "image":
            return "[image]"
        case "audio":
            return "[audio]"
        default:
            return ""
        }
    }

    /// Maps an ACP tool_call payload onto ToolCallModel (defaults per the spec:
    /// kind "other", status "pending").
    static func parseToolCall(_ update: [String: Any]) -> ToolCallModel {
        let content = parseToolCallContent(update["content"])
        return ToolCallModel(
            id: (update["toolCallId"] as? String) ?? "acp-tool-unidentified",
            title: (update["title"] as? String) ?? "Tool call",
            kind: (update["kind"] as? String).flatMap(ToolCallModel.Kind.init(rawValue:)) ?? .other,
            status: (update["status"] as? String).flatMap(ToolCallModel.Status.init(rawValue:)) ?? .pending,
            contentText: content.text,
            diff: content.diff,
            rawInput: prettyJSON(update["rawInput"]),
            rawOutput: prettyJSON(update["rawOutput"])
        )
    }

    /// Maps an ACP tool_call_update payload; only the fields present on the wire are
    /// non-nil, so the store mutates just what changed.
    static func parseToolCallUpdate(_ update: [String: Any]) -> ToolCallUpdate {
        let content = update["content"] != nil ? parseToolCallContent(update["content"]) : (text: "", diff: nil)
        return ToolCallUpdate(
            id: (update["toolCallId"] as? String) ?? "acp-tool-unidentified",
            title: update["title"] as? String,
            kind: (update["kind"] as? String).flatMap(ToolCallModel.Kind.init(rawValue:)),
            status: (update["status"] as? String).flatMap(ToolCallModel.Status.init(rawValue:)),
            contentText: update["content"] != nil ? content.text : nil,
            diff: content.diff,
            rawInput: prettyJSON(update["rawInput"]),
            rawOutput: prettyJSON(update["rawOutput"])
        )
    }

    /// Splits a tool call's content array into its text (regular ContentBlocks) and the
    /// first diff. Terminal content is noted in the text (the live terminal panel is M5).
    private static func parseToolCallContent(_ content: Any?) -> (text: String, diff: ToolCallDiff?) {
        guard let entries = content as? [[String: Any]] else {
            return ("", nil)
        }
        var texts: [String] = []
        var diff: ToolCallDiff?
        for entry in entries {
            switch entry["type"] as? String {
            case "content":
                let text = contentText(entry["content"])
                if !text.isEmpty {
                    texts.append(text)
                }
            case "diff":
                if diff == nil, let path = entry["path"] as? String, let newText = entry["newText"] as? String {
                    diff = ToolCallDiff(path: path, oldText: entry["oldText"] as? String, newText: newText)
                }
            case "terminal":
                texts.append("[terminal output]")
            default:
                break
            }
        }
        return (texts.joined(separator: "\n\n"), diff)
    }

    private static func prettyJSON(_ value: Any?) -> String? {
        guard let value else {
            return nil
        }
        if let text = value as? String {
            return text
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}

#endif
