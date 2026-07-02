// Add-ons/ActionUIChat/Sources/ChatModel.swift
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

import Foundation
import CoreGraphics

/// The party a transcript item belongs to. A transport maps its own participants
/// onto these keys; the JSON `roles` map then resolves each key to a side / label
/// / tint. In single-alignment (M1) `side` is ignored and only label / tint matter.
enum ChatRole: String, Sendable, Hashable {
    case local      // the local user (composer input)
    case agent      // an AI agent
    case remote     // the other party in person-to-person chat
    case system     // session / system notices
}

/// A single conversation message. `text` accumulates streaming deltas; `isStreaming`
/// is true while the turn that owns it is still in flight (drives the streaming row
/// treatment and the Stop affordance). The `id` is stable so the transcript's
/// `LazyVStack` does not re-diff finalized rows while the last message streams.
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: ChatRole
    var text: String
    var isStreaming: Bool
}

/// A standalone image transcript element. Chat splits an image and its accompanying text into SEPARATE
/// items (a person dropping a photo with a comment, an agent returning an image block), so an image is its
/// own element, not part of a message's `text`. `pixelSize` is the source's natural size when the transport
/// knows it - it lets the transcript reserve exact space so the picture hydrates without reflowing the
/// scroll position. `alt` is the accessibility / fallback description.
struct ChatImage: Sendable, Equatable {
    let url: URL
    let alt: String
    let pixelSize: CGSize?

    init(url: URL, alt: String = "", pixelSize: CGSize? = nil) {
        self.url = url
        self.alt = alt
        self.pixelSize = pixelSize
    }
}

/// A tool invocation surfaced by an agentic transport, rendered as a card in the
/// transcript. The shape mirrors ACP's `tool_call` payload (kind / status vocabularies
/// are ACP's) so the ACP transport maps 1:1, but nothing here is wire-specific - the
/// scripted local transport builds these too. `contentText` is the call's textual
/// content (Markdown, joined across content blocks); `diff` and the raw input / output
/// are optional detail the card can disclose.
struct ToolCallModel: Identifiable, Equatable, Sendable {

    /// What the call does; drives the card icon. ACP's `kind` vocabulary.
    enum Kind: String, Sendable {
        case read, edit, delete, move, search, execute, think, fetch, other
    }

    /// Lifecycle state; drives the card's status indicator. ACP's `status` vocabulary.
    enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case failed
    }

    let id: String
    var title: String
    var kind: Kind
    var status: Status
    var contentText: String
    var diff: ToolCallDiff?
    var rawInput: String?      // pretty-printed JSON, when the transport provides it
    var rawOutput: String?
}

/// A proposed or applied file change carried inside a tool call's content
/// (ACP's `diff` ToolCallContent). Rendered as a code preview in M3; a real
/// side-by-side diff viewer is an M5 surface.
struct ToolCallDiff: Equatable, Sendable {
    let path: String
    let oldText: String?
    let newText: String
}

/// A partial mutation of an existing tool call (ACP's `tool_call_update`):
/// only non-nil fields change on the card.
struct ToolCallUpdate: Sendable {
    let id: String
    var title: String?
    var kind: ToolCallModel.Kind?
    var status: ToolCallModel.Status?
    var contentText: String?
    var diff: ToolCallDiff?
    var rawInput: String?
    var rawOutput: String?

    init(id: String, title: String? = nil, kind: ToolCallModel.Kind? = nil,
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
struct PermissionRequest: Identifiable, Equatable, Sendable {

    struct Option: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable {
            case allowOnce = "allow_once"
            case allowAlways = "allow_always"
            case rejectOnce = "reject_once"
            case rejectAlways = "reject_always"

            var allows: Bool {
                self == .allowOnce || self == .allowAlways
            }
        }
        let id: String        // the wire optionId, echoed back in the response
        let name: String
        let kind: Kind
    }

    let id: String            // the request ID, echoed back in the response
    let toolCallID: String?   // the gated call, when the transport correlates one
    let title: String
    let options: [Option]
}

/// One step of the agent's evolving task plan (ACP `plan`). The agent re-emits the
/// WHOLE plan as it progresses, so the store replaces the list rather than merging.
/// ACP plan entries carry no IDs; identity is positional, assigned by the transport.
struct PlanEntry: Identifiable, Equatable, Sendable {
    enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
    let id: Int               // positional (index in the emitted plan)
    let content: String
    let priority: String?     // "high" | "medium" | "low" when the agent sends one; display-only
    let status: Status
}

/// Token / cost usage for the session (OpenCode's `usage_update`: tokens used out of
/// the context window, plus an optional cost). Agents that do not report usage never
/// emit it; the status line simply stays empty.
struct UsageInfo: Equatable, Sendable {
    let used: Int
    let size: Int?            // context window size, when reported
    let costAmount: Double?
    let costCurrency: String?
}

/// One selectable session option advertised by the agent at session start (OpenCode's
/// session/new `configOptions`: model, mode, ...; the ACP spec's `modes` sketch maps
/// onto the same shape). Displayed read-only in the status line (M5 part 1); the
/// interactive setter is M5 part 3.
struct SessionConfigOption: Identifiable, Equatable, Sendable {
    struct Choice: Equatable, Sendable {
        let value: String
        let name: String
        let description: String?
    }
    let id: String            // e.g. "model", "mode"
    let name: String          // display name, e.g. "Session Mode"
    let category: String?     // "model" | "mode" | agent-specific
    var currentValue: String  // a Choice.value; `current_mode_update` mutates the mode option's
    let options: [Choice]

    var currentChoiceName: String? {
        options.first(where: { $0.value == currentValue })?.name
    }
}

/// A slash command the agent currently offers (ACP `available_commands_update`,
/// re-emitted whole as the set changes). Selecting one just fills the composer:
/// commands are SENT as ordinary prompt text ("/name args") for the agent to
/// interpret - there is no separate command channel.
struct SlashCommand: Identifiable, Equatable, Sendable {
    let name: String          // without the leading slash
    let description: String

    var id: String {
        name
    }
}

/// A heterogeneous, arrival-ordered transcript entry. M1 carries messages plus
/// system / error notices; M3 adds thoughts (reasoning, `ChatMessage`-shaped but
/// visually folded) and tool-call cards. Plan / terminal panels are M5 side
/// surfaces and live outside the transcript.
enum ChatItem: Identifiable, Equatable {
    case message(ChatMessage)
    case thought(ChatMessage)
    case toolCall(ToolCallModel)
    case image(id: String, role: ChatRole, image: ChatImage)
    case system(id: String, text: String)
    case error(id: String, text: String)

    var id: String {
        switch self {
        case .message(let message):  return message.id
        case .thought(let thought):  return thought.id
        case .toolCall(let call):    return call.id
        case .image(let id, _, _):   return id
        case .system(let id, _):     return id
        case .error(let id, _):      return id
        }
    }
}

/// Normalized inbound event a transport emits. Transport-agnostic: the `local`
/// transport emits the message lifecycle (plus the agentic cases in its scripted
/// "agentic" demo style); the ACP transport emits the full vocabulary.
enum ChatEvent: Sendable {
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
    case image(itemID: String, role: ChatRole, image: ChatImage)   // a standalone image element
    case system(text: String)
    case error(message: String, recoverable: Bool)
}

/// Normalized outbound command the UI hands a transport. A plain-text user turn,
/// a cancel, and the answer to a pending permission request (`optionID` nil means
/// the request was dismissed / the turn cancelled - ACP's `cancelled` outcome).
/// Attachments (ContentBlock[]) and mode changes arrive with later milestones.
enum ChatCommand: Sendable {
    case prompt(text: String)
    case cancel
    case permissionResponse(requestID: String, optionID: String?)
}
