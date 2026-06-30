// Add-ons/ActionUIChat/Sources/ChatModel.swift
//
// Transport-agnostic value types shared across the Chat add-on:
//   - the render model:        ChatRole, ChatMessage, ChatItem
//   - the normalized inbound:  ChatEvent  (what a transport emits)
//   - the normalized outbound: ChatCommand (what the UI sends a transport)
//
// The ChatEvent / ChatCommand vocabularies are a SUPERSET shaped by the richest
// transport (ACP); a simpler transport emits only a subset. This M1 file defines
// the subset the `local` transport and the single-alignment transcript need -
// plain message lifecycle plus system / error notices. Richer events (tool-call
// cards, plans, permission requests, diffs, terminals) arrive with the ACP
// transport (Private/chat-element-design.md, milestones M3 / M5) and extend these
// enums; nothing here is ACP-specific.

import Foundation

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

/// A heterogeneous, arrival-ordered transcript entry. M1 carries messages plus
/// system / error notices; later milestones add `.toolCall`, `.diff`, `.thought`,
/// etc. (routed here or to side surfaces by ChatStore's router).
enum ChatItem: Identifiable, Equatable {
    case message(ChatMessage)
    case system(id: String, text: String)
    case error(id: String, text: String)

    var id: String {
        switch self {
        case .message(let message): return message.id
        case .system(let id, _):    return id
        case .error(let id, _):     return id
        }
    }
}

/// Normalized inbound event a transport emits. Transport-agnostic: the `local`
/// transport emits only the message-lifecycle and system / error cases; a future
/// ACP transport emits the same cases for chat text and adds richer ones.
enum ChatEvent: Sendable {
    case sessionReady(sessionID: String)
    case messageStart(itemID: String, role: ChatRole)
    case messageDelta(itemID: String, text: String)        // streaming token(s)
    case messageEnd(itemID: String, stopReason: String?)
    case system(text: String)
    case error(message: String, recoverable: Bool)
}

/// Normalized outbound command the UI hands a transport. M1 sends a plain-text
/// user turn and a cancel; attachments (ContentBlock[]) and the richer commands
/// (permission responses, mode changes) arrive with later milestones.
enum ChatCommand: Sendable {
    case prompt(text: String)
    case cancel
}
