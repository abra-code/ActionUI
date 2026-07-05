// Add-ons/ActionUIChat/Sources/Core/Chat.swift
/*
 Sample JSON for Chat:
 {
   "type": "Chat",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   "config": {               // Optional: NON-VISUAL operational settings (the element-level config block,
                             //           sibling of properties). Hosts can inject runtime/session-specific
                             //           values via setElementConfig between loading and showing a document.
     "protocol": "local",                 // Optional: transport selector. "local" (default) is built in and streams a
                                          //           scripted reply. Every other protocol is provided by a separate
                                          //           transport module the host links and registers; the umbrella
                                          //           ActionUIChat product bundles them and wires them in register().
                                          //           "openai-sse" (the ActionUIChatOpenAI module) streams an
                                          //           OpenAI-compatible /v1/chat/completions endpoint (llama-server,
                                          //           mlx_lm.server, ...). "acp" (the ActionUIChatACP module, macOS
                                          //           only: the agent is a subprocess) runs an Agent Client Protocol
                                          //           agent over stdio. A protocol whose module the host did not
                                          //           register degrades to "local".
     "transport": { "echo": true }        // Optional: protocol-specific settings (interpreted by the chosen transport).
                                          //           "local" honors "echo" (default true: stream a demo reply),
                                          //           "reply" ("echo" default | "markdown" | "agentic": a scripted
                                          //           agent turn with thoughts, tool calls, and a permission gate),
                                          //           and "chunkMs" (demo streaming pace, default 45).
                                          //           "openai-sse" requires "baseURL" (the endpoint, e.g.
                                          //           "http://127.0.0.1:8080/v1") and honors "model" (default "auto":
                                          //           resolved from GET {baseURL}/models), "apiKey" (default ""),
                                          //           "systemPrompt" (default ""), and "params" (merged into the
                                          //           request body, e.g. { "temperature": 0.8, "max_tokens": 0 };
                                          //           max_tokens 0 means unlimited and is omitted).
                                          //           "acp" requires "command" (the agent argv, e.g. ["claude-code-acp"])
                                          //           and honors "cwd" (the session root; "~" expands, default: the
                                          //           host's current directory) and "mcpServers" (passed to the agent).
   },
   "properties": {
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
       "toolCalls": "inline",             //   "inline" (default: a status card; its detail - file reads,
                                          //   diffs, raw I/O - stays FOLDED until tapped, and long content
                                          //   is truncated) | "collapsed" (a compact one-line row) |
                                          //   "hidden". "panel" renders inline for now.
       "thoughts": "collapsed",           //   "collapsed" (default: folded) | "inline" | "hidden"
       "plan": "panel",                   //   The agent's task plan, pinned ABOVE the transcript (never
                                          //   interleaved as chat): "panel" (default: expanded) |
                                          //   "collapsed" (pinned, folded) | "hidden".
       "diffs": "inline"                  //   Agent-proposed file diffs, rendered in the tool card's detail
                                          //   as a real line diff (the standalone DiffView component: hunks,
                                          //   old / new line-number gutters, +/- markers): "inline" (default)
                                          //   | "hidden" (dropped). "collapsed" / "panel" are accepted but
                                          //   coerced to inline (the card's fold already covers collapsing;
                                          //   a diff side panel is a later surface).
     },
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
 bodies plus standalone image items (M2); the agentic surfaces (M3) - streamed reasoning folded behind
 a "Thoughts" disclosure, tool-call cards that mutate in place through their pending / in-progress /
 completed / failed lifecycle, and a permission gate that pins an approval card above the composer and
 pauses input until answered ("surfaces" routes each of these; the local transport's "agentic" reply
 style demonstrates them all); and the ACP transport (M3, macOS) - the element launches any Agent
 Client Protocol agent as a subprocess (newline-delimited JSON-RPC over stdio), negotiates capabilities
 (advertising no fs / terminal services), opens a session, and demuxes the session/update stream onto
 those same surfaces, with session/request_permission wired to the approval card and Stop wired to
 session/cancel. And the first M5 session-status surfaces: the agent's evolving plan pinned above the
 transcript (routed by surfaces.plan; ACP `plan`), plus a status line under the composer showing the
 session's model / mode and token / cost usage (ACP `usage_update`) - the local transport's "agentic"
 reply style demos all of it with no agent installed. The model / mode entries are MENUS when the
 agent offers choices: selecting sends session/set_config_option (with the spec's session/set_mode /
 set_model as fallbacks) and the display updates on the agent's confirmation, never optimistically.
 Plus the composer's slash-command menu: when a transport advertises commands (ACP
 `available_commands_update`), typing "/" lists and filters them and a tap fills the draft - the
 command still sends as ordinary prompt text for the agent to interpret. And agent-proposed file diffs
 now render inside the tool card's detail as a real line diff (the DiffView product of the sibling
 ActionUIDiff add-on, which these tool cards consume: hunks, old / new line-number gutters, +/-
 markers; routed by surfaces.diffs, "hidden" drops them). Transports are separate, statically linked
 modules behind a registry: "local" is the only built-in, and a host adds a protocol by linking its
 module (ActionUIChatOpenAI for "openai-sse", ActionUIChatACP for "acp") and calling its register() - or
 by linking the umbrella ActionUIChat product, whose register() wires every bundled transport at once; a
 protocol whose module was not registered degrades to "local". The "openai-sse" transport streams an
 OpenAI-compatible /v1/chat/completions endpoint (llama-server, mlx_lm.server, or any compatible server):
 plain streaming chat with reasoning folded into thoughts, tool calls rendered as (unexecuted) cards, and
 token usage in the status bar - no agent process required. Dual alignment and the remaining M5 surfaces
 (terminals, multi-session) arrive in later milestones (see Private/chat-element-design.md).

 Observable state: the element manages its own transcript model internally (no single scalar value), so
 it does not expose getElementValue / setElementValue yet; host interaction is via the action IDs above.
 The non-visual settings (protocol, transport) live in the element-level "config" block and are host-
 injectable via setElementConfig - the canonical embedding loads a static document, injects the
 runtime/session-specific transport (resolved agent path, working directory), then shows the view
 (see DemoApp). The transport is consumed when the chat starts; a later config change takes effect
 on the element's next rebuild.

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.

 Implementation note: the "Chat" element lives in the ActionUIChatCore module and conforms to ActionUI's
 public ActionUIViewConstruction contract. The type and its witnesses are internal - an internal type
 conforming to a public protocol keeps internal witnesses. The module's public surface is small:
 ActionUIChatCore.register() (element + built-in "local" transport), registerTransport(_:factory:), and the
 frozen transport contract a transport module builds against (ChatTransport, ChatEvent, ChatCommand,
 ChatTransportConfig, ChatLogger, and the value types those carry). The umbrella ActionUIChat.register()
 registers the element and every bundled transport in one call.
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

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // model.config is the element's live NON-VISUAL config block (protocol,
        // transport), stored verbatim by core; ChatConfig checks it as it reads.
        let config = ChatConfig(properties: properties, config: model.config, logger: logger)
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
