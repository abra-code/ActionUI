// Add-ons/ActionUIChat/Sources/ChatStore.swift
//
// The @MainActor source of truth for one `Chat` element, and the router that
// pre-filters the transport's event stream.
//
// ChatStore owns the render model (the transcript `items` and the streaming flag),
// builds the transport from the config, drains its `ChatEvent` stream, and reduces
// each event into a store mutation (`route(_:)`). `route` is the PRE-FILTER the
// design centers on: chat text lands in the transcript, system / error notices are
// their own items, and (in later milestones) tool calls / plans / permissions are
// routed to side surfaces - all driven by `surfaces` config, so a non-agentic
// transport that never emits those events renders a plain conversation with no
// special cases. Outbound, it appends the user's message optimistically, fires the
// host-facing action IDs, and hands a normalized `ChatCommand` to the transport.

import Foundation
import SwiftUI
import ActionUI

@MainActor
final class ChatStore: ObservableObject {

    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var isStreaming = false       // a reply turn is in flight
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

    /// Finishes the transport (ending its event stream so the drain task completes)
    /// and tears down. Called from the view's `.onDisappear`; idempotent.
    func teardown() {
        eventTask?.cancel()
        eventTask = nil
        streamBuffers.removeAll()
        let transport = self.transport
        self.transport = nil
        Task { await transport?.stop() }
    }

    // MARK: - Router (pre-filter): ChatEvent -> store mutation

    private func route(_ event: ChatEvent) {
        switch event {
        case .sessionReady(let sessionID):
            logger.log("Chat session ready: \(sessionID)", .verbose)

        case .messageStart(let itemID, let role):
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
            let finalText = streamBuffers[itemID]
            streamBuffers[itemID] = nil
            if let index = messageIndex(itemID) {
                mutateMessage(at: index) {
                    if let finalText {
                        $0.text = finalText
                    }
                    $0.isStreaming = false
                }
            }
            isStreaming = false
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
            if case .message(let message) = items[index], message.text != text {
                mutateMessage(at: index) { $0.text = text }
            }
        }
    }

    // MARK: - Helpers

    private func messageIndex(_ id: String) -> Int? {
        items.firstIndex {
            if case .message(let message) = $0 {
                return message.id == id
            }
            return false
        }
    }

    private func mutateMessage(at index: Int, _ transform: (inout ChatMessage) -> Void) {
        guard case .message(var message) = items[index] else { return }
        transform(&message)
        items[index] = .message(message)
    }

    private func fire(_ actionID: String?) {
        guard let actionID, !actionID.isEmpty else { return }
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0)
    }

    deinit {
        eventTask?.cancel()
    }
}
