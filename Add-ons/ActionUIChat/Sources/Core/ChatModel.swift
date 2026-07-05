// Add-ons/ActionUIChat/Sources/Core/ChatModel.swift
//
// Transport-agnostic value types shared across the Chat add-on:
//   - the render model:        ChatRole, ChatMessage, ChatItem
//   - the normalized inbound:  ChatEvent  (what a transport emits)
//   - the normalized outbound: ChatCommand (what the UI sends a transport)
//
// The ChatEvent / ChatCommand vocabularies are a SUPERSET shaped by the richest
// transport (ACP); a simpler transport emits only a subset. M1 defined the plain
// message lifecycle plus system / error notices; M3 adds the agentic vocabulary -
// reasoning (thoughts), tool-call cards, and permission requests - shaped 1:1
// after ACP's session/update payloads so the ACP transport maps directly, but
// still transport-agnostic (the scripted local transport emits them too). Plans,
// terminals, and slash commands arrive with the M5 side panels
// (Private/chat-element-design.md).
//
// PUBLIC API NOTE: ChatEvent / ChatCommand and every value type they carry are the
// frozen transport-facing contract (P0-6). A transport lives in its own module
// (ActionUIChatACP, ActionUIChatOpenAI, or a host's own) and depends on
// ActionUIChatCore only for these types plus the ChatTransport protocol; so they are
// `public` with explicit `public init`s. The render model that never crosses the
// transport boundary (ChatMessage, ChatItem) stays internal.

import Foundation
import CoreGraphics

/// The party a transcript item belongs to. A transport maps its own participants
/// onto these keys; the JSON `roles` map then resolves each key to a side / label
/// / tint. In single-alignment (M1) `side` is ignored and only label / tint matter.
public enum ChatRole: String, Sendable, Hashable, Codable {
    case local      // the local user (composer input)
    case agent      // an AI agent
    case remote     // the other party in person-to-person chat
    case system     // session / system notices
}

/// A single conversation message. `text` accumulates streaming deltas; `isStreaming`
/// is true while the turn that owns it is still in flight (drives the streaming row
/// treatment and the Stop affordance). The `id` is stable so the transcript's
/// `LazyVStack` does not re-diff finalized rows while the last message streams.
///
/// A message enters and leaves a transport only as itemID + role + text deltas
/// (ChatEvent), never as this whole value, so it is not part of the transport API - but
/// it IS part of the persisted transcript (P0-2), so it is public and Codable. The
/// transient `isStreaming` render flag is NOT serialized: a loaded message is always
/// final (decodes with isStreaming == false).
public struct ChatMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let role: ChatRole
    public var text: String
    public var isStreaming: Bool

    public init(id: String, role: ChatRole, text: String, isStreaming: Bool) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.role = try container.decode(ChatRole.self, forKey: .role)
        self.text = try container.decode(String.self, forKey: .text)
        self.isStreaming = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
    }
}

/// A standalone image transcript element. Chat splits an image and its accompanying text into SEPARATE
/// items (a person dropping a photo with a comment, an agent returning an image block), so an image is its
/// own element, not part of a message's `text`. `pixelSize` is the source's natural size when the transport
/// knows it - it lets the transcript reserve exact space so the picture hydrates without reflowing the
/// scroll position. `alt` is the accessibility / fallback description.
public struct ChatImage: Sendable, Equatable, Codable {
    public let url: URL
    public let alt: String
    public let pixelSize: CGSize?

    public init(url: URL, alt: String = "", pixelSize: CGSize? = nil) {
        self.url = url
        self.alt = alt
        self.pixelSize = pixelSize
    }

    // Serializes by source reference (the URL / path), never pixel data. `pixelSize` is
    // flattened to explicit width/height so the JSON shape is stable and self-documenting.
    private enum CodingKeys: String, CodingKey {
        case url, alt, pixelWidth, pixelHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(URL.self, forKey: .url)
        self.alt = try container.decodeIfPresent(String.self, forKey: .alt) ?? ""
        if let width = try container.decodeIfPresent(Double.self, forKey: .pixelWidth),
           let height = try container.decodeIfPresent(Double.self, forKey: .pixelHeight) {
            self.pixelSize = CGSize(width: width, height: height)
        } else {
            self.pixelSize = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(alt, forKey: .alt)
        if let pixelSize {
            try container.encode(Double(pixelSize.width), forKey: .pixelWidth)
            try container.encode(Double(pixelSize.height), forKey: .pixelHeight)
        }
    }
}

/// A tool invocation surfaced by an agentic transport, rendered as a card in the
/// transcript. The shape mirrors ACP's `tool_call` payload (kind / status vocabularies
/// are ACP's) so the ACP transport maps 1:1, but nothing here is wire-specific - the
/// scripted local transport builds these too. `contentText` is the call's textual
/// content (Markdown, joined across content blocks); `diff` and the raw input / output
/// are optional detail the card can disclose.
public struct ToolCallModel: Identifiable, Equatable, Sendable, Codable {

    /// Persistence coding keys (P0-2): pinned so the on-disk format does not drift.
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, status, contentText, diff, rawInput, rawOutput
    }

    /// What the call does; drives the card icon. ACP's `kind` vocabulary.
    public enum Kind: String, Sendable, Codable {
        case read, edit, delete, move, search, execute, think, fetch, other
    }

    /// Lifecycle state; drives the card's status indicator. ACP's `status` vocabulary.
    public enum Status: String, Sendable, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
    }

    public let id: String
    public var title: String
    public var kind: Kind
    public var status: Status
    public var contentText: String
    public var diff: ToolCallDiff?
    public var rawInput: String?      // pretty-printed JSON, when the transport provides it
    public var rawOutput: String?

    public init(id: String, title: String, kind: Kind, status: Status, contentText: String,
                diff: ToolCallDiff? = nil, rawInput: String? = nil, rawOutput: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.contentText = contentText
        self.diff = diff
        self.rawInput = rawInput
        self.rawOutput = rawOutput
    }
}

/// A proposed or applied file change carried inside a tool call's content
/// (ACP's `diff` ToolCallContent). Rendered as a code preview in M3; a real
/// side-by-side diff viewer is an M5 surface.
public struct ToolCallDiff: Equatable, Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case path, oldText, newText
    }

    public let path: String
    public let oldText: String?
    public let newText: String

    public init(path: String, oldText: String?, newText: String) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
    }
}

/// A partial mutation of an existing tool call (ACP's `tool_call_update`):
/// only non-nil fields change on the card.
public struct ToolCallUpdate: Sendable {
    public let id: String
    public var title: String?
    public var kind: ToolCallModel.Kind?
    public var status: ToolCallModel.Status?
    public var contentText: String?
    public var diff: ToolCallDiff?
    public var rawInput: String?
    public var rawOutput: String?

    public init(id: String, title: String? = nil, kind: ToolCallModel.Kind? = nil,
                status: ToolCallModel.Status? = nil, contentText: String? = nil,
                diff: ToolCallDiff? = nil, rawInput: String? = nil, rawOutput: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.contentText = contentText
        self.diff = diff
        self.rawInput = rawInput
        self.rawOutput = rawOutput
    }
}

/// An agent's request to run a gated tool call (ACP's `session/request_permission`).
/// The UI blocks the call until the user picks one of the agent-offered options (or
/// the turn is cancelled); the option kinds are ACP's standard four.
public struct PermissionRequest: Identifiable, Equatable, Sendable {

    public struct Option: Identifiable, Equatable, Sendable {
        public enum Kind: String, Sendable {
            case allowOnce = "allow_once"
            case allowAlways = "allow_always"
            case rejectOnce = "reject_once"
            case rejectAlways = "reject_always"

            public var allows: Bool {
                self == .allowOnce || self == .allowAlways
            }
        }
        public let id: String        // the wire optionId, echoed back in the response
        public let name: String
        public let kind: Kind

        public init(id: String, name: String, kind: Kind) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    public let id: String            // the request ID, echoed back in the response
    public let toolCallID: String?   // the gated call, when the transport correlates one
    public let title: String
    public let options: [Option]

    public init(id: String, toolCallID: String?, title: String, options: [Option]) {
        self.id = id
        self.toolCallID = toolCallID
        self.title = title
        self.options = options
    }
}

/// One step of the agent's evolving task plan (ACP `plan`). The agent re-emits the
/// WHOLE plan as it progresses, so the store replaces the list rather than merging.
/// ACP plan entries carry no IDs; identity is positional, assigned by the transport.
public struct PlanEntry: Identifiable, Equatable, Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case id, content, priority, status
    }
    public enum Status: String, Sendable, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
    public let id: Int               // positional (index in the emitted plan)
    public let content: String
    public let priority: String?     // "high" | "medium" | "low" when the agent sends one; display-only
    public let status: Status

    public init(id: Int, content: String, priority: String?, status: Status) {
        self.id = id
        self.content = content
        self.priority = priority
        self.status = status
    }
}

/// Token / cost usage for the session (OpenCode's `usage_update`: tokens used out of
/// the context window, plus an optional cost). Agents that do not report usage never
/// emit it; the status line simply stays empty.
public struct UsageInfo: Equatable, Sendable, Codable {
    private enum CodingKeys: String, CodingKey {
        case used, size, costAmount, costCurrency
    }

    public let used: Int
    public let size: Int?            // context window size, when reported
    public let costAmount: Double?
    public let costCurrency: String?

    public init(used: Int, size: Int?, costAmount: Double?, costCurrency: String?) {
        self.used = used
        self.size = size
        self.costAmount = costAmount
        self.costCurrency = costCurrency
    }
}

/// One selectable session option advertised by the agent at session start (OpenCode's
/// session/new `configOptions`: model, mode, ...; the ACP spec's `modes` sketch maps
/// onto the same shape). Displayed read-only in the status line (M5 part 1); the
/// interactive setter is M5 part 3.
public struct SessionConfigOption: Identifiable, Equatable, Sendable {
    public struct Choice: Equatable, Sendable {
        public let value: String
        public let name: String
        public let description: String?

        public init(value: String, name: String, description: String?) {
            self.value = value
            self.name = name
            self.description = description
        }
    }
    public let id: String            // e.g. "model", "mode"
    public let name: String          // display name, e.g. "Session Mode"
    public let category: String?     // "model" | "mode" | agent-specific
    public var currentValue: String  // a Choice.value; `current_mode_update` mutates the mode option's
    public let options: [Choice]

    public init(id: String, name: String, category: String?, currentValue: String, options: [Choice]) {
        self.id = id
        self.name = name
        self.category = category
        self.currentValue = currentValue
        self.options = options
    }

    public var currentChoiceName: String? {
        options.first(where: { $0.value == currentValue })?.name
    }
}

/// A slash command the agent currently offers (ACP `available_commands_update`,
/// re-emitted whole as the set changes). Selecting one just fills the composer:
/// commands are SENT as ordinary prompt text ("/name args") for the agent to
/// interpret - there is no separate command channel.
public struct SlashCommand: Identifiable, Equatable, Sendable {
    public let name: String          // without the leading slash
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }

    public var id: String {
        name
    }
}

/// A heterogeneous, arrival-ordered transcript entry. M1 carries messages plus
/// system / error notices; M3 adds thoughts (reasoning, `ChatMessage`-shaped but
/// visually folded) and tool-call cards. Plan / terminal panels are M5 side
/// surfaces and live outside the transcript.
///
/// The store's render model - transports emit ChatEvents and the store builds ChatItems
/// from them - and, since P0-2, the unit of the persisted transcript, so it is public and
/// Codable. Codable uses a stable `type` discriminator ("message" / "thought" / "toolCall"
/// / "image" / "system" / "error") so the on-disk format does not drift.
public enum ChatItem: Identifiable, Equatable, Sendable, Codable {
    case message(ChatMessage)
    case thought(ChatMessage)
    case toolCall(ToolCallModel)
    case image(id: String, role: ChatRole, image: ChatImage)
    case system(id: String, text: String)
    case error(id: String, text: String)

    public var id: String {
        switch self {
        case .message(let message):  return message.id
        case .thought(let thought):  return thought.id
        case .toolCall(let call):    return call.id
        case .image(let id, _, _):   return id
        case .system(let id, _):     return id
        case .error(let id, _):      return id
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, message, toolCall, id, role, image, text
    }

    private enum ItemType: String, Codable {
        case message, thought, toolCall, image, system, error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .message:
            self = .message(try container.decode(ChatMessage.self, forKey: .message))
        case .thought:
            self = .thought(try container.decode(ChatMessage.self, forKey: .message))
        case .toolCall:
            self = .toolCall(try container.decode(ToolCallModel.self, forKey: .toolCall))
        case .image:
            self = .image(id: try container.decode(String.self, forKey: .id),
                          role: try container.decode(ChatRole.self, forKey: .role),
                          image: try container.decode(ChatImage.self, forKey: .image))
        case .system:
            self = .system(id: try container.decode(String.self, forKey: .id),
                           text: try container.decode(String.self, forKey: .text))
        case .error:
            self = .error(id: try container.decode(String.self, forKey: .id),
                          text: try container.decode(String.self, forKey: .text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let message):
            try container.encode(ItemType.message, forKey: .type)
            try container.encode(message, forKey: .message)
        case .thought(let thought):
            try container.encode(ItemType.thought, forKey: .type)
            try container.encode(thought, forKey: .message)
        case .toolCall(let call):
            try container.encode(ItemType.toolCall, forKey: .type)
            try container.encode(call, forKey: .toolCall)
        case .image(let id, let role, let image):
            try container.encode(ItemType.image, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(role, forKey: .role)
            try container.encode(image, forKey: .image)
        case .system(let id, let text):
            try container.encode(ItemType.system, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
        case .error(let id, let text):
            try container.encode(ItemType.error, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
        }
    }
}

/// The serializable form of a whole chat session (P0-2). The element has no scalar value: a host
/// RESTORES a saved session at runtime by injecting this (as JSON / a dict / a string) into
/// `states["content"]` (setElementState / setElementStateFromString), and persists incrementally
/// the other way, per finalized entry, through `entryActionID`. `version` pins the format; `items`
/// is the transcript; `usage` / `plan` are the latest status surfaces; `title` is an optional
/// app-owned label passed through untouched (the component never interprets it).
public struct ChatTranscript: Equatable, Sendable, Codable {
    public let version: Int
    public let items: [ChatItem]
    public let usage: UsageInfo?
    public let plan: [PlanEntry]
    public let title: String?

    public init(version: Int = 1, items: [ChatItem], usage: UsageInfo? = nil,
                plan: [PlanEntry] = [], title: String? = nil) {
        self.version = version
        self.items = items
        self.usage = usage
        self.plan = plan
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case version, items, usage, plan, title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.items = try container.decodeIfPresent([ChatItem].self, forKey: .items) ?? []
        self.usage = try container.decodeIfPresent(UsageInfo.self, forKey: .usage)
        self.plan = try container.decodeIfPresent([PlanEntry].self, forKey: .plan) ?? []
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(usage, forKey: .usage)
        if !plan.isEmpty {
            try container.encode(plan, forKey: .plan)
        }
        try container.encodeIfPresent(title, forKey: .title)
    }

    /// Decodes a restored value into a transcript: a ChatTranscript passes through; a JSON object /
    /// string / data is decoded. Returns nil for anything else (an unrelated value), which callers
    /// ignore. Used by both the store's `states["content"]` restore observation and the
    /// `properties.content` pre-populated load.
    public static func decode(from value: Any?) -> ChatTranscript? {
        if let transcript = value as? ChatTranscript {
            return transcript
        }
        let data: Data?
        switch value {
        case let string as String:
            data = string.data(using: .utf8)
        case let raw as Data:
            data = raw
        case let object as [String: Any]:
            data = try? JSONSerialization.data(withJSONObject: object)
        default:
            data = nil
        }
        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(ChatTranscript.self, from: data)
    }
}

/// Normalized inbound event a transport emits. Transport-agnostic: the `local`
/// transport emits the message lifecycle (plus the agentic cases in its scripted
/// "agentic" demo style); the ACP transport emits the full vocabulary.
public enum ChatEvent: Sendable {
    case sessionReady(sessionID: String, configOptions: [SessionConfigOption])
    case messageStart(itemID: String, role: ChatRole)
    case messageDelta(itemID: String, text: String)        // streaming token(s)
    case messageEnd(itemID: String, stopReason: String?)   // nil stopReason: the message closed but the
                                                           // turn continues (e.g. a tool call interleaves,
                                                           // ACP); non-nil: the whole turn ended
    case thoughtDelta(itemID: String, text: String)        // streaming reasoning; no explicit start/end,
                                                           // a thought closes when another item begins
    case toolCall(ToolCallModel)                           // a new tool invocation
    case toolCallUpdate(ToolCallUpdate)                    // mutate that card in place
    case permissionRequest(PermissionRequest)              // blocks the gated call until answered
    case plan([PlanEntry])                                 // the agent's WHOLE current plan (replace, not merge)
    case usage(UsageInfo)                                  // token / cost status (latest wins)
    case currentModeChanged(modeID: String)                // ACP current_mode_update; updates the mode option
    case commandsAvailable([SlashCommand])                 // the agent's WHOLE current command set (replace)
    case configOptionsChanged([SessionConfigOption])       // the refreshed option set (a setter's confirmation)
    case image(itemID: String, role: ChatRole, image: ChatImage)   // a standalone image element
    case system(text: String)
    case error(message: String, recoverable: Bool)
}

/// Normalized outbound command the UI hands a transport. A plain-text user turn,
/// a cancel, the answer to a pending permission request (`optionID` nil means
/// the request was dismissed / the turn cancelled - ACP's `cancelled` outcome),
/// and a session-option change from the status-line menus (mode / model / ...).
/// Attachments (ContentBlock[]) arrive with later milestones.
public enum ChatCommand: Sendable {
    case prompt(text: String)
    case cancel
    case permissionResponse(requestID: String, optionID: String?)
    case setConfigOption(optionID: String, value: String)
}
