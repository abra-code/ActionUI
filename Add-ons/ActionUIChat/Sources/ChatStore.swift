// Add-ons/ActionUIChat/Sources/ChatStore.swift
//
// The @MainActor source of truth for one `Chat` element, and the router that
// pre-filters the transport's event stream.
//
// ChatStore owns the render model (the transcript `items`, the streaming flag, and
// the pending-permission queue), builds the transport from the config, drains its
// `ChatEvent` stream, and reduces each event into a store mutation (`route(_:)`).
// `route` is the PRE-FILTER the design centers on: chat text lands in the
// transcript; thoughts and tool-call cards are transcript items whose presentation
// (and whether they appear at all) is driven by the `surfaces` config; permission
// requests queue for the approval card and are answered back through the transport.
// A non-agentic transport that never emits those events renders a plain
// conversation with no special cases. Outbound, it appends the user's message
// optimistically, fires the host-facing action IDs, and hands a normalized
// `ChatCommand` to the transport.

import Foundation
import SwiftUI
import ActionUI

@MainActor
final class ChatStore: ObservableObject {

    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var isStreaming = false       // a reply turn is in flight
    @Published private(set) var pendingPermissions: [PermissionRequest] = []   // FIFO; the card shows the head
    @Published var draft: String = ""                     // composer text

    let config: ChatConfig
    let windowUUID: String
    let elementID: Int
    let logger: any ActionUILogger

    private var transport: (any ChatTransport)?
    private var eventTask: Task<Void, Never>?
    private var localCounter = 0

    // Coalescing: streaming deltas accumulate per item here and are flushed to the published
    // transcript at most ~20 Hz, so the Markdown re-parse runs on a fixed cadence instead of once
    // per token (however fast the transport streams).
    private var streamBuffers: [String: String] = [:]
    private var flushPending = false

    init(config: ChatConfig, windowUUID: String, elementID: Int, logger: any ActionUILogger) {
        self.config = config
        self.windowUUID = windowUUID
        self.elementID = elementID
        self.logger = logger
    }

    /// Builds the transport (once) and starts draining its event stream. Called from
    /// the view's `.onAppear`.
    func start() {
        guard transport == nil else { return }
        let transport = ChatTransportFactory.make(config, logger: logger)
        self.transport = transport
        eventTask = Task { [weak self] in
            await transport.start()
            for await event in transport.events {
                self?.route(event)
            }
        }
    }

    // MARK: - User intent

    /// Submits the current composer draft, if non-empty.
    func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        send(text)
    }

    /// Appends the user's message optimistically, fires `sendActionID` /
    /// `messageActionID`, and forwards a `.prompt` to the transport.
    func send(_ text: String) {
        localCounter += 1
        items.append(.message(ChatMessage(id: "user-\(localCounter)", role: .local, text: text, isStreaming: false)))
        fire(config.sendActionID)
        fire(config.messageActionID)
        let transport = self.transport
        Task { await transport?.send(.prompt(text: text)) }
    }

    /// Requests cancellation of the in-flight turn.
    func stop() {
        fire(config.stopActionID)
        let transport = self.transport
        Task { await transport?.send(.cancel) }
    }

    /// Answers a pending permission request. `optionID` is one of the request's
    /// option IDs, or nil for a dismissal (the cancelled outcome). Dequeues the
    /// request and forwards the response to the transport, which unblocks (or
    /// abandons) the gated tool call.
    func respondToPermission(_ requestID: String, optionID: String?) {
        pendingPermissions.removeAll { $0.id == requestID }
        let transport = self.transport
        Task { await transport?.send(.permissionResponse(requestID: requestID, optionID: optionID)) }
    }

    /// Finishes the transport (ending its event stream so the drain task completes)
    /// and tears down. Called from the view's `.onDisappear`; idempotent.
    func teardown() {
        eventTask?.cancel()
        eventTask = nil
        streamBuffers.removeAll()
        pendingPermissions.removeAll()
        let transport = self.transport
        self.transport = nil
        Task { await transport?.stop() }
    }

    // MARK: - Router (pre-filter): ChatEvent -> store mutation

    // Internal (not private) so tests can drive the reduction directly.
    func route(_ event: ChatEvent) {
        switch event {
        case .sessionReady(let sessionID):
            logger.log("Chat session ready: \(sessionID)", .verbose)

        case .messageStart(let itemID, let role):
            finalizeOpenThoughts()
            items.append(.message(ChatMessage(id: itemID, role: role, text: "", isStreaming: true)))
            streamBuffers[itemID] = ""
            if role != .local {
                isStreaming = true
            }

        case .messageDelta(let itemID, let text):
            if streamBuffers[itemID] != nil {
                streamBuffers[itemID]? += text
                scheduleFlush()
            } else {
                // A delta with no prior start: open an agent message implicitly.
                items.append(.message(ChatMessage(id: itemID, role: .agent, text: "", isStreaming: true)))
                streamBuffers[itemID] = text
                isStreaming = true
                scheduleFlush()
            }

        case .messageEnd(let itemID, _):
            // Final flush is immediate (do not wait for the coalescing tick), then finalize.
            // The turn is over: any still-open thought closes and a permission request the
            // turn abandoned (e.g. on cancel) is moot.
            finalizeOpenThoughts()
            let finalText = streamBuffers[itemID]
            streamBuffers[itemID] = nil
            if let index = messageIndex(itemID) {
                mutateStreamingText(at: index) {
                    if let finalText {
                        $0.text = finalText
                    }
                    $0.isStreaming = false
                }
            }
            isStreaming = false
            pendingPermissions.removeAll()
            fire(config.messageActionID)

        case .thoughtDelta(let itemID, let text):
            if config.surfaces.thoughts == .hidden {
                return
            }
            if streamBuffers[itemID] != nil {
                streamBuffers[itemID]? += text
            } else {
                items.append(.thought(ChatMessage(id: itemID, role: .agent, text: "", isStreaming: true)))
                streamBuffers[itemID] = text
                isStreaming = true
            }
            scheduleFlush()

        case .toolCall(let call):
            finalizeOpenThoughts()
            if config.surfaces.toolCalls == .hidden {
                return
            }
            items.append(.toolCall(call))
            isStreaming = true

        case .toolCallUpdate(let update):
            if config.surfaces.toolCalls == .hidden {
                return
            }
            guard let index = toolCallIndex(update.id) else {
                logger.log("Chat tool_call_update for unknown call '\(update.id)'; ignoring", .verbose)
                return
            }
            guard case .toolCall(var call) = items[index] else { return }
            if let title = update.title {
                call.title = title
            }
            if let kind = update.kind {
                call.kind = kind
            }
            if let status = update.status {
                call.status = status
            }
            if let contentText = update.contentText {
                call.contentText = contentText
            }
            if let diff = update.diff {
                call.diff = diff
            }
            if let rawInput = update.rawInput {
                call.rawInput = rawInput
            }
            if let rawOutput = update.rawOutput {
                call.rawOutput = rawOutput
            }
            items[index] = .toolCall(call)

        case .permissionRequest(let request):
            finalizeOpenThoughts()
            pendingPermissions.append(request)
            isStreaming = true
            fire(config.approveToolActionID)

        case .image(let itemID, let role, let image):
            items.append(.image(id: itemID, role: role, image: image))
            fire(config.messageActionID)

        case .system(let text):
            localCounter += 1
            items.append(.system(id: "system-\(localCounter)", text: text))

        case .error(let message, _):
            localCounter += 1
            items.append(.error(id: "error-\(localCounter)", text: message))
            fire(config.errorActionID)
        }
    }

    // MARK: - Coalescing

    /// Ensures one flush is scheduled ~50 ms out (≈20 Hz). Repeated deltas within the window do not
    /// stack up - they all land in `streamBuffers` and are applied by the single pending flush.
    private func scheduleFlush() {
        if flushPending {
            return
        }
        flushPending = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self?.applyBufferedText()
        }
    }

    private func applyBufferedText() {
        flushPending = false
        for (itemID, text) in streamBuffers {
            guard let index = messageIndex(itemID) else {
                continue
            }
            if streamingText(at: index) != text {
                mutateStreamingText(at: index) { $0.text = text }
            }
        }
    }

    /// Closes every still-streaming thought: applies its buffered text and clears the
    /// streaming flag. A thought has no explicit end event - it ends when the next
    /// item (message, tool call, permission request) begins, or when the turn does.
    private func finalizeOpenThoughts() {
        for index in items.indices {
            guard case .thought(var thought) = items[index], thought.isStreaming else {
                continue
            }
            if let buffered = streamBuffers.removeValue(forKey: thought.id) {
                thought.text = buffered
            }
            thought.isStreaming = false
            items[index] = .thought(thought)
        }
    }

    // MARK: - Helpers

    /// Index of the message or thought with this id (the two item kinds that stream text).
    private func messageIndex(_ id: String) -> Int? {
        items.firstIndex {
            switch $0 {
            case .message(let message):  return message.id == id
            case .thought(let thought):  return thought.id == id
            default:                     return false
            }
        }
    }

    private func toolCallIndex(_ id: String) -> Int? {
        items.firstIndex {
            if case .toolCall(let call) = $0 {
                return call.id == id
            }
            return false
        }
    }

    private func streamingText(at index: Int) -> String? {
        switch items[index] {
        case .message(let message):  return message.text
        case .thought(let thought):  return thought.text
        default:                     return nil
        }
    }

    private func mutateStreamingText(at index: Int, _ transform: (inout ChatMessage) -> Void) {
        switch items[index] {
        case .message(var message):
            transform(&message)
            items[index] = .message(message)
        case .thought(var thought):
            transform(&thought)
            items[index] = .thought(thought)
        default:
            break
        }
    }

    private func fire(_ actionID: String?) {
        guard let actionID, !actionID.isEmpty else { return }
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0)
    }

    deinit {
        eventTask?.cancel()
    }
}
