// Add-ons/ActionUIChat/Sources/Chat.swift
/*
 Sample JSON for Chat:
 {
   "type": "Chat",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "protocol": "local",                 // Optional: transport; "local" (default) streams a scripted reply.
                                          //           "acp" / "openai-sse" / "anthropic-sse" / "custom" arrive later.
     "appearance": {                      // Optional: transcript appearance
       "alignment": "single",             //   "single" (default): leading / full-width, parties by tint + label.
                                          //   "dual" (later): incoming leading, outgoing trailing.
       "showRoleLabels": true,            //   Show a small role label above each message; default true.
       "theme": "auto"                    //   "auto" | "light" | "dark"; default "auto".
     },
     "roles": {                           // Optional: per-role label / tint (and side, used by "dual" later)
       "local": { "label": "You",   "tint": "accent" },
       "agent": { "label": "Agent", "tint": "secondary" }
     },
     "input": {                           // Optional: composer
       "enabled": true,                   //   Default true.
       "placeholder": "Message",          //   Default "Message".
       "submitOn": "return"               //   "return" (default), "modifier-return" (Cmd+Return), "shift-return-newline".
     },
     "surfaces": {                        // Optional: routing for agentic transport items
       "toolCalls": "inline",             //   "inline" (default: expanded card) | "collapsed" | "hidden"
                                          //   ("panel" arrives with the M5 side panels; it renders inline for now).
       "thoughts": "collapsed"            //   "collapsed" (default: folded) | "inline" | "hidden"
     },
     "transport": { "echo": true },       // Optional: protocol-specific config (validated by the chosen transport).
                                          //           "local" honors "echo" (default true: stream a demo reply),
                                          //           "reply" ("echo" default | "markdown" | "agentic": a scripted
                                          //           agent turn with thoughts, tool calls, and a permission gate),
                                          //           and "chunkMs" (demo streaming pace, default 45).
     "sendActionID": "chat.send",         // Optional: fired when the user submits a message
     "stopActionID": "chat.stop",         // Optional: fired when the user cancels an in-flight turn
     "messageActionID": "chat.message",   // Optional: fired per finalized message (user and agent)
     "errorActionID": "chat.error",       // Optional: fired on a transport / parse error
     "approveToolActionID": "chat.tool.approve" // Optional: fired when an agent requests tool permission
   }
 }

 A native chat surface, implemented as an ActionUI add-on (registered via ActionUIChat.register()).
 A transcript above a composer; the transport (selected by "protocol") drives the conversation and the
 element pre-filters its stream so chat text lands in the transcript. The element is GENERIC: the same
 element backs AI-agent chat and person-to-person chat - the transport and appearance differ, not the view.

 Landed so far: the "local" transport and single-alignment transcript (M1); streaming Markdown message
 bodies plus standalone image items (M2); and the agentic surfaces (M3, this version) - streamed
 reasoning folded behind a "Thoughts" disclosure, tool-call cards that mutate in place through their
 pending / in-progress / completed / failed lifecycle, and a permission gate that pins an approval card
 above the composer and pauses input until answered ("surfaces" routes each of these; the local
 transport's "agentic" reply style demonstrates them all). The ACP wire transport, dual alignment, and
 the side panels (plans, terminals, diff viewer) arrive in later milestones
 (see Private/chat-element-design.md).

 Observable state: the element manages its own transcript model internally (no single scalar value), so
 it does not expose getElementValue / setElementValue yet; host interaction is via the action IDs above.

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.

 Implementation note: conforms to ActionUI's public ActionUIViewConstruction contract. The type and its
 witnesses are internal to this module - an internal type conforming to a public protocol keeps internal
 witnesses; only ActionUIChat.register() is public.
 */

import SwiftUI
import ActionUI

struct Chat: ActionUIViewConstruction {

    // The element owns a rich internal model (transcript, streaming buffer, transport), so it has no
    // single scalar runtime value - mirroring container-style elements (valueType Void).
    static var valueType: Any.Type = Void.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        ChatConfig.validate(properties, logger)
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, _, windowUUID, properties, logger in
        let config = ChatConfig(properties, logger)
        return ChatRootView(config: config, windowUUID: windowUUID, elementID: element.id, logger: logger)
    }

    // Baseline View modifiers (frame, padding, background, ...) are applied by the registry.
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // Void-value element: no initial value to seed (mirrors VStack and other containers).
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    // The transcript is engine-internal (driven by the transport), not a runtime-insertable container.
    static var insertableContainers: [String: ContainerShape]? = nil
}
