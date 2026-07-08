// Add-ons/ActionUIChat/Sources/Core/ChatStore.swift
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
import Combine
import ActionUI

/// The element's content channel: `states["content"]`, the same place Table / List keep their
/// content. A host RESTORES a saved session by injecting a serialized transcript here at runtime
/// (setElementState / setElementStateFromString), AFTER the interface is built; the store observes
/// it and loads. This is one-way (restore-in only): the store never writes it back - persistence
/// flows the other way, per finalized entry, through `entryActionID`. Abstracted over ViewModel so
/// the restore path is testable with a fake.
@MainActor
protocol ChatContentSource: AnyObject {
    /// Observes `states["content"]`; the handler is called with the current value on subscription and
    /// on every subsequent change (matching @Published semantics). Cancel to stop.
    func observeChatContent(_ handler: @escaping (Any?) -> Void) -> AnyCancellable
    /// Observes `states["config"]` - the host-injected operational config (protocol + transport) -
    /// with the same current-value-on-subscription-and-on-change semantics. Cancel to stop.
    func observeChatConfig(_ handler: @escaping (Any?) -> Void) -> AnyCancellable
}

extension ViewModel: ChatContentSource {
    func observeChatContent(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        $states.sink { handler($0["content"]) }
    }
    func observeChatConfig(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        $states.sink { handler($0["config"]) }
    }
}

@MainActor
final class ChatStore: ObservableObject {

    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var isStreaming = false       // a reply turn is in flight
    @Published private(set) var isConfigured = false      // a viable transport has been built from states["config"]; the composer gates on this
    @Published private(set) var pendingPermissions: [PermissionRequest] = []   // FIFO; the card shows the head
    @Published private(set) var plan: [PlanEntry] = []    // the agent's current plan (whole-list replace)
    @Published private(set) var usage: UsageInfo?         // latest token/cost status, when the agent reports it
    @Published private(set) var configOptions: [SessionConfigOption] = []   // model/mode/... advertised at session start
    @Published private(set) var availableCommands: [SlashCommand] = []      // the agent's slash commands (composer menu)
    @Published var draft: String = ""                     // composer text

    private(set) var title: String?                       // app-owned session label, passed through the transcript

    let config: ChatConfig
    let windowUUID: String
    let elementID: Int
    let logger: any ActionUILogger

    private var transport: (any ChatTransport)?
    private var eventTask: Task<Void, Never>?
    private var localCounter = 0
    private var didLoadInitial = false

    // Config-injection seam (states["config"]). The operational config (protocol + transport) is NOT
    // document-declared: the store observes states["config"] and builds the transport once it first
    // resolves to a VIABLE config, then FREEZES - `didConfigure` latches, `resolvedTransportConfig`
    // holds the frozen decision, and later states["config"] changes are ignored. On reappearance the
    // torn-down transport is rebuilt from the frozen decision (not from a possibly-changed state).
    private var didConfigure = false
    private var resolvedTransportConfig: ChatTransportConfig?
    private var configCancellable: AnyCancellable?

    // Coalescing: streaming deltas accumulate per item here and are flushed to the published
    // transcript at most ~20 Hz, so the Markdown re-parse runs on a fixed cadence instead of once
    // per token (however fast the transport streams).
    private var streamBuffers: [String: String] = [:]
    private var flushPending = false

    // Session transcript seam (P0-2). A saved session RESTORES into `states["content"]` at runtime
    // (setElementState / setElementStateFromString), observed here. `lastLoadedContent` dedups so a
    // given content value loads once. Persistence flows the other way, per finalized entry, through
    // `entryActionID` - the store never writes `states["content"]` back.
    private weak var contentSource: (any ChatContentSource)?
    private var lastLoadedContent: ChatTranscript?
    private var contentCancellable: AnyCancellable?
    private var entrySequence = 0

    init(config: ChatConfig, windowUUID: String, elementID: Int, logger: any ActionUILogger, contentSource: (any ChatContentSource)? = nil) {
        self.config = config
        self.windowUUID = windowUUID
        self.elementID = elementID
        self.logger = logger
        self.contentSource = contentSource
    }

    /// Loads any pre-populated transcript (a document `properties.content`, a testing convenience) once,
    /// (re)starts observing runtime restores through `states["content"]`, and - unless `readOnly` -
    /// builds the transport and drains its event stream. Called from the view's `.onAppear`; safe to
    /// call again after `.onDisappear` (which tears the transport / subscription down but preserves the
    /// transcript): the pre-populated load runs only the first time, and the transport is rebuilt.
    func start() {
        // One-time pre-populated load. A document `properties.content` (a preview / testing convenience,
        // NOT the production path) seeds the transcript before any transport runs.
        if !didLoadInitial {
            didLoadInitial = true
            if let raw = config.initialContentRaw {
                if let transcript = ChatTranscript.decode(from: raw) {
                    applyLoadedTranscript(transcript)
                    lastLoadedContent = transcript
                } else {
                    logger.log("Chat properties.content is not a decodable transcript; ignoring", .warning)
                }
            }
        }
        // (Re)subscribe to runtime restores through states["content"] (setElementState[FromString]).
        // The dedup against `lastLoadedContent` ignores the subscription's immediate delivery of a
        // value already loaded (e.g. the pre-populated content).
        if contentCancellable == nil, let contentSource {
            contentCancellable = contentSource.observeChatContent { [weak self] newContent in
                self?.reconcileRestoredContent(newContent)
            }
        }

        // readOnly is the history-viewer mode: no transport, no config observation (ChatRootView
        // gates the composer / menus).
        guard !config.readOnly else {
            return
        }

        // (Re)subscribe to the host-injected operational config through states["config"]. The sink
        // delivers the current value on subscription AND on every change, so INIT-time injection is
        // never "too late": whenever a viable config arrives, reconcileConfig builds the transport.
        if configCancellable == nil, let contentSource {
            configCancellable = contentSource.observeChatConfig { [weak self] newConfig in
                self?.reconcileConfig(newConfig)
            }
        }

        // Reappearance: the transport was torn down on disappear but the config decision is frozen -
        // rebuild it from the frozen decision (ignoring any post-freeze states["config"] change).
        if didConfigure, transport == nil, let resolved = resolvedTransportConfig,
           let rebuilt = ChatTransportRegistry.shared.makeIfViable(
               protocolName: resolved.protocolName, transport: resolved.settings, logger: logger) {
            attach(rebuilt)
        }
    }

    // MARK: - Config injection (states["config"]) -> deferred, frozen transport

    /// Handles a host-injected operational config from states["config"]. Builds the transport the
    /// FIRST time the config resolves to a viable one, then FREEZES: `didConfigure` latches so a later
    /// states["config"] change is ignored for this element (a new element is needed to switch
    /// transport). A config that is not yet viable (e.g. openai-sse before its baseURL, or acp before
    /// its command) does NOT freeze - the element stays inert and waits for a completer config.
    /// Internal so tests can drive an injection directly (as the config subscription does).
    func reconcileConfig(_ raw: Any?) {
        guard !config.readOnly, !didConfigure else {
            return
        }
        guard let (protocolName, transportSettings) = Self.parseTransportConfig(raw) else {
            return   // no config object yet (states["config"] absent / not a dict) - stay inert
        }
        guard let built = ChatTransportRegistry.shared.makeIfViable(
                protocolName: protocolName, transport: transportSettings, logger: logger) else {
            logger.log("Chat config for protocol '\(protocolName)' is not viable yet; awaiting a complete states[\"config\"]", .verbose)
            return
        }
        // First viable config wins and freezes.
        didConfigure = true
        resolvedTransportConfig = ChatTransportConfig(protocolName: protocolName, settings: transportSettings)
        isConfigured = true
        attach(built)
    }

    /// Parses states["config"] into (protocolName, transport). Accepts a dict, a JSON string, or JSON
    /// Data (matching setElementState / setElementStateFromString). A missing `protocol` defaults to
    /// "local"; a missing `transport` is an empty object. Returns nil when there is no config object.
    private static func parseTransportConfig(_ raw: Any?) -> (protocolName: String, transport: [String: Any])? {
        let dict: [String: Any]?
        switch raw {
        case let value as [String: Any]:
            dict = value
        case let string as String:
            dict = (string.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
        case let data as Data:
            dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        default:
            dict = nil
        }
        guard let dict else {
            return nil
        }
        let protocolName = (dict["protocol"] as? String) ?? ChatTransportRegistry.reservedLocalName
        let transportSettings = (dict["transport"] as? [String: Any]) ?? [:]
        return (protocolName, transportSettings)
    }

    /// Installs a built transport and starts draining its event stream.
    private func attach(_ transport: any ChatTransport) {
        self.transport = transport
        // If a transcript was restored before the transport existed (content injected before a
        // viable config), seed the new transport's wire history from it so a continue carries
        // context. For a fresh session `items` is empty, so this primes an empty history.
        primeTransportFromItems()
        eventTask = Task { [weak self] in
            await transport.start()
            for await event in transport.events {
                self?.route(event)
            }
        }
    }

    /// Seeds the active transport's wire history from the current transcript's message items,
    /// so a continued conversation is sent with its prior turns as context (and an empty /
    /// cleared transcript resets the wire). No-op when no transport exists yet (attach()
    /// re-primes once one is built). Message items only (role + text); the transport maps
    /// role -> its own wire format. Called synchronously from applyLoadedTranscript and attach,
    /// always before any subsequent prompt, so no command-channel serialization is needed.
    private func primeTransportFromItems() {
        guard let transport else { return }
        // Reserve every loaded item id first, so a continued turn cannot mint an id the transport
        // already used in this transcript (ChatTransport.reserveIDs). This passes ALL ids -
        // including thoughts and tool cards, which primeHistory omits - because a transport's
        // per-turn id counter is shared across item kinds (a reasoning-only turn leaves a thought
        // id with no paired message id, invisible to a messages-only prime).
        transport.reserveIDs(seen: items.map(\.id))
        let messages: [ChatMessage] = items.compactMap { item in
            if case let .message(message) = item { return message }
            return nil
        }
        transport.primeHistory(messages)
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
        let itemID = "user-\(localCounter)"
        let message = ChatMessage(id: itemID, role: .local, text: text, isStreaming: false)
        items.append(.message(message))
        fire(config.sendActionID)
        fire(config.messageActionID)
        fireEntry(type: "message", id: itemID, data: ChatItem.message(message))
        let transport = self.transport
        Task { await transport?.send(.prompt(text: text)) }
    }

    /// Requests cancellation of the in-flight turn.
    func stop() {
        fire(config.stopActionID)
        let transport = self.transport
        Task { await transport?.send(.cancel) }
    }

    /// Changes a session option (mode / model / ...) from the status-line menus.
    /// Deliberately NOT optimistic: the display updates when the transport confirms
    /// (.configOptionsChanged, or the agent's own current_mode_update), so a failed
    /// change never needs a revert.
    func setConfigOption(_ optionID: String, value: String) {
        let transport = self.transport
        Task { await transport?.send(.setConfigOption(optionID: optionID, value: value)) }
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
        contentCancellable?.cancel()
        contentCancellable = nil
        configCancellable?.cancel()
        configCancellable = nil
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
        case .sessionReady(let sessionID, let options):
            configOptions = options
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

        case .messageEnd(let itemID, let stopReason):
            // Final flush is immediate (do not wait for the coalescing tick), then finalize.
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
                if case .message(let finalized) = items[index] {
                    fireEntry(type: "message", id: itemID, data: ChatItem.message(finalized))
                }
            }
            fire(config.messageActionID)
            // A nil stopReason closes only this message (a segmented transport - ACP -
            // interleaves tool calls mid-turn). A non-nil stopReason ends the whole turn:
            // streaming state clears, and a permission request the turn abandoned (e.g.
            // on cancel) is moot.
            if stopReason != nil {
                isStreaming = false
                pendingPermissions.removeAll()
            }

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
            fireEntryForCompletedToolCall(call)

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
            fireEntryForCompletedToolCall(call)

        case .permissionRequest(let request):
            finalizeOpenThoughts()
            pendingPermissions.append(request)
            isStreaming = true
            fire(config.approveToolActionID)

        case .plan(let entries):
            if config.surfaces.plan == .hidden {
                return
            }
            // The agent re-emits its WHOLE plan as it progresses: replace, never merge.
            plan = entries
            fireEntry(type: "plan", id: nil, data: entries)

        case .usage(let info):
            usage = info
            fireEntry(type: "usage", id: nil, data: info)

        case .currentModeChanged(let modeID):
            // The spec's current_mode_update names only the new value; it targets the
            // mode option (matched by category, falling back to the "mode" id).
            guard let index = configOptions.firstIndex(where: { $0.category == "mode" || $0.id == "mode" }) else {
                logger.log("Chat current_mode_update '\(modeID)' with no mode option; ignoring", .verbose)
                return
            }
            configOptions[index].currentValue = modeID

        case .commandsAvailable(let commands):
            // The agent re-emits its WHOLE command set as it changes: replace, never merge.
            availableCommands = commands

        case .configOptionsChanged(let options):
            // A setter's confirmation: the refreshed option set replaces the display.
            configOptions = options

        case .image(let itemID, let role, let image):
            items.append(.image(id: itemID, role: role, image: image))
            fire(config.messageActionID)
            fireEntry(type: "image", id: itemID, data: ChatItem.image(id: itemID, role: role, image: image))

        case .system(let text):
            localCounter += 1
            let itemID = "system-\(localCounter)"
            items.append(.system(id: itemID, text: text))
            fireEntry(type: "system", id: itemID, data: ChatItem.system(id: itemID, text: text))

        case .error(let message, _):
            localCounter += 1
            let itemID = "error-\(localCounter)"
            items.append(.error(id: itemID, text: message))
            fire(config.errorActionID)
            fireEntry(type: "error", id: itemID, data: ChatItem.error(id: itemID, text: message))
        }
    }

    // MARK: - Session transcript seam: restore-in + incremental per-entry persistence

    /// Handles a transcript a host restored into `states["content"]` (setElementState /
    /// setElementStateFromString). Ignores content already loaded (the subscription's immediate
    /// current-value delivery, or a repeated identical restore); a new transcript replaces the
    /// session. Internal so tests can drive a restore directly (as the content subscription does).
    func reconcileRestoredContent(_ newContent: Any?) {
        guard let transcript = ChatTranscript.decode(from: newContent), transcript != lastLoadedContent else {
            return
        }
        applyLoadedTranscript(transcript)
        lastLoadedContent = transcript
    }

    /// Replaces the session state with a loaded transcript: items render in their final states
    /// (no live continuations), the streaming / permission / buffer state is cleared, and the
    /// status surfaces are restored. Appended turns (if a transport runs) land after the loaded items.
    private func applyLoadedTranscript(_ transcript: ChatTranscript) {
        items = transcript.items
        usage = transcript.usage
        plan = transcript.plan
        title = transcript.title
        isStreaming = false
        pendingPermissions.removeAll()
        streamBuffers.removeAll()
        // Advance the id counter past any store-generated ids (user-/system-/error-N) in the loaded
        // transcript, so a subsequent user/system/error item cannot collide with a loaded one (which
        // would break ForEach identity and messageIndex lookups).
        let generatedPrefixes = ["user-", "system-", "error-"]
        let maxSuffix = transcript.items.compactMap { item -> Int? in
            let id = item.id
            for prefix in generatedPrefixes where id.hasPrefix(prefix) {
                return Int(id.dropFirst(prefix.count))
            }
            return nil
        }.max()
        if let maxSuffix {
            localCounter = max(localCounter, maxSuffix)
        }
        // Seed the transport's wire history from the loaded transcript so typing continues the
        // conversation WITH its prior turns as context (P0-2 continue-in). An empty transcript
        // (New Chat clear) resets the wire. No-op if the transport is not built yet.
        primeTransportFromItems()
    }

    /// The envelope fired to entryActionID: a monotonic sequence, the finalized entry's type
    /// and id (for idempotent upsert on the app side), and the entry's JSON.
    private struct EntryEnvelope<Payload: Encodable>: Encodable {
        let sequence: Int
        let type: String
        let id: String?
        let data: Payload
    }

    /// Fires `entryActionID` (when configured) with a JSON envelope for one finalized transcript
    /// entry, so the host can persist incrementally without polling. Never called on streaming deltas.
    private func fireEntry<Payload: Encodable>(type: String, id: String?, data: Payload) {
        guard let actionID = config.entryActionID, !actionID.isEmpty else {
            return
        }
        // Compute the next sequence but commit it only if the payload encodes, so an encode failure
        // does not burn a number (a host detecting dropped events by a sequence gap would false-positive).
        let next = entrySequence + 1
        let envelope = EntryEnvelope(sequence: next, type: type, id: id, data: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let jsonData = try? encoder.encode(envelope), let json = String(data: jsonData, encoding: .utf8) else {
            logger.log("Chat: could not encode entry payload for '\(type)'; skipping", .warning)
            return
        }
        entrySequence = next
        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: json)
    }

    /// Fires the "toolCall" entry whenever a tool call is in (or reaches) a terminal (completed /
    /// failed) state. It re-fires if a terminal call receives further updates - some transports deliver
    /// the terminal status and the final output/diff in SEPARATE updates - so the LAST entry always
    /// carries the final content. The host upserts by type+id, so the re-fires collapse to the latest.
    private func fireEntryForCompletedToolCall(_ call: ToolCallModel) {
        guard call.status == .completed || call.status == .failed else {
            return
        }
        fireEntry(type: "toolCall", id: call.id, data: ChatItem.toolCall(call))
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
            fireEntry(type: "thought", id: thought.id, data: ChatItem.thought(thought))
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
