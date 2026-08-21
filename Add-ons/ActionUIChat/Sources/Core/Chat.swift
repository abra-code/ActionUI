// Add-ons/ActionUIChat/Sources/Core/Chat.swift
/*
 Sample JSON for Chat:
 {
   "type": "Chat",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   // protocol + transport are NOT declared in the document - a host injects them at runtime into
   // states["config"] AFTER the element is built (see the "Host-injected transport" note below the
   // sample). Shape: { "protocol": "local" | "openai-sse" | "acp" | "acp-remote",
   //                   "transport": { ...protocol-specific } }
   //   local:      "echo" (default true: stream a demo reply), "reply" ("echo"|"markdown"|"agentic"),
   //               "chunkMs" (demo streaming pace, default 45).
   //   openai-sse: requires "baseURL" (e.g. "http://127.0.0.1:8080/v1"); honors "model" (default "auto":
   //               resolved from GET {baseURL}/models), "apiKey", "systemPrompt", "params" (merged into
   //               the request body, e.g. { "temperature": 0.8, "max_tokens": 0 }).
   //   acp (macOS, subprocess): requires "command" (the agent argv, e.g. ["claude-code-acp"]); honors
   //               "cwd" ("~" expands, default: host cwd) and "mcpServers". A protocol whose module the
   //               host did not link/register degrades to "local".
   //   acp-remote: an ACP agent on ANOTHER machine, reached over a WebSocket to a chatview-acp-bridge.
   //               Owns no subprocess, so unlike "acp" it is NOT macOS-only. Honors "session"
   //               ("new" by default, or a bridge session id to rejoin) and "resumeAfterSeq" (the
   //               afterSeq from the last checkpoint - ignored unless "session" names a session).
   //               THE ONLY protocol that produces resumeCheckpointActionID cursors; the other three
   //               have no resumable server side, so a host wiring that action ID against them will
   //               store entries forever and never see a checkpoint.
   "properties": {
     "appearance": {                      // Optional: transcript appearance
       "alignment": "single",             //   "single" (default): leading / full-width, parties by tint + label.
                                          //   "dual": outgoing (self) trailing with the role tint, incoming leading -
                                          //   the messaging-app layout for person-to-person / group chat.
       "showRoleLabels": true,            //   Show a small role label above each message; default true.
       "theme": "auto",                   //   "auto" | "light" | "dark"; default "auto".
       "showTimestamps": true,            //   Time caption under a run + day separators; default true in "dual",
                                          //   false in "single". Renders only on items that carry a timestamp.
       "showAvatars": false,              //   Sender avatar (initials disc when none resolves) beside incoming
                                          //   messages; default false (opt-in).
       "showDeliveryStatus": true         //   Delivery caption (Sending / Sent / Delivered / Read, Failed w/ retry)
                                          //   under the last own message of a run; default true. Renders only on
                                          //   messages that carry a status (v1 messages never do).
     },
     "roles": {                           // Optional: per-role label / tint / side. In "dual", self (role "local"
                                          //           or a participant marked isSelf) aligns trailing and others
                                          //           leading; an explicit per-role "side" overrides that.
       "local": { "label": "You",   "tint": "accent" },
       "agent": { "label": "Agent", "tint": "secondary" }
     },
     "features": {                        // Optional: person-to-person / group affordances the document enables.
       "reactions": false,                //   All default false (opt-in). An affordance appears only when the
       "editing": false,                  //   document enables it AND the active transport advertises the matching
       "deletion": false,                 //   capability. reactions: emoji reactions (quick row + chips). editing:
       "replies": false                   //   edit own messages ("(edited)" badge). deletion: delete own messages
     },                                   //   ("Message deleted" tombstone). replies: reply to / quote a message.
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
     "approveToolActionID": "chat.tool.approve", // Optional: fired when an agent requests tool permission
     "attachActionID": "chat.attach",     // Optional: shows the composer's attach (paperclip) button; fired on tap.
                                          //           The host mediates the picker and hands the file to its transport
                                          //           out of band. The ONLY person-to-person host action ID - every
                                          //           other v2 affordance (reactions, edits, replies, deletes, read
                                          //           marks, paging, typing) flows to the transport as a command.
     "entryActionID": "chat.entry",       // Optional: fired per FINALIZED transcript entry (message, thought,
                                          //           completed/failed tool call, image, system, error, plan,
                                          //           usage) with a JSON envelope { sequence, type, id, data } as
                                          //           the action context, for crash-safe incremental persistence.
                                          //           A message that states["lead"] lines were placed in front of
                                          //           also carries them, as placed, under "lead".
                                          //           Never fired on streaming deltas.
     "resumeCheckpointActionID": "chat.checkpoint",
                                          // Optional: the resume cursor that pairs with entryActionID, as
                                          //           { afterSeq, sessionId } JSON in the action context. Fired only
                                          //           while the transcript is QUIESCENT (a turn boundary, or catching
                                          //           up after an attach), never mid-stream, and only when
                                          //           entryActionID is ALSO set - a host that is not storing entries
                                          //           is not offered a cursor. Persist it atomically with the
                                          //           entries: a newer cursor loses what is in between, an older one
                                          //           duplicates it, and storing neither half is always safe. Feed it
                                          //           back as the transport's "resumeAfterSeq" (with "session").
                                          //           Only the "acp-remote" protocol produces one.
     "readOnly": false                    // Optional (default false): read-only viewer mode - hides the composer and
                                          //           menus and starts NO transport ("protocol" may be omitted). Pair
                                          //           with a runtime setElementState("content", ...) to show a saved session.
                                          // (Session data is NOT carried in the document - see "Session transcript" below.
                                          //  "properties.content" pre-populates a transcript for previews / testing only.)
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
 session/cancel. The same module also registers "acp-remote", which speaks that protocol to an agent
 on ANOTHER machine over a WebSocket to a chatview-acp-bridge, on every platform - it owns no
 subprocess, and it is the only transport that emits resume checkpoints. And the first M5
 session-status surfaces: the agent's evolving plan pinned above the transcript (routed by
 surfaces.plan; ACP `plan`), plus a status line under the composer showing the
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
 modules behind a registry: "local" (a scripted echo / agentic demo) and "local-p2p" (a scripted
 person-to-person / group demo) are built in, and a host adds another protocol by linking its
 module (ActionUIChatOpenAI for "openai-sse", ActionUIChatACP for both "acp" and "acp-remote")
 and calling its register() - or by linking the umbrella ActionUIChat product, whose register()
 wires every bundled transport at once; a
 protocol whose module was not registered degrades to "local". The "openai-sse" transport streams an
 OpenAI-compatible /v1/chat/completions endpoint (llama-server, mlx_lm.server, or any compatible server):
 plain streaming chat with reasoning folded into thoughts, tool calls rendered as (unexecuted) cards, and
 token usage in the status bar - no agent process required.

 And person-to-person / group chat (appearance.alignment "dual"): your messages align trailing with the
 role tint, everyone else's leading, the messaging-app layout. It adds - all additive, all optional, so a
 v1 document is unchanged - message timestamps and day separators, per-sender names and avatars (or an
 initials disc), delivery status (Sending / Sent / Delivered / Read, and Failed with tap-to-retry), emoji
 reactions, replies (a tappable quoted-excerpt block), message editing and deletion (a tombstone), member
 and call events (centered captions), file and voice-message items (a transfer progress bar / an audio
 player), a typing indicator, and paged history (scroll to the top to load earlier). Each interactive
 affordance appears only when the document enables it (the "features" object) AND the active transport
 advertises the matching capability; those conversation actions flow to the transport as commands, and the
 sole new host action ID is "attachActionID" (the composer's attach button). The built-in "local-p2p"
 transport scripts all of it with no wire (the ChatPeople / ChatGroup examples). The remaining surfaces
 (terminals, multi-session) arrive in later milestones (see Private/chat-element-design.md).

 Session transcript (P0-2): the element has no scalar value - its session transcript is CONTENT. A host
 RESTORES a saved session at runtime by injecting a serialized ChatTranscript (version, items, usage, plan,
 title) into states["content"], AFTER the interface is built - the same place Table / List keep their
 content, and the right vehicle for session DATA (a static UI document describes how to build the interface,
 not the conversation, and does not scale to carrying a transcript). Restore with a STABLE representation so
 REPEATED restores work (e.g. a session switcher reusing one element): pass a JSON string (or a native
 object) via setElementState("content", ...) - the store decodes either. setElementStateFromString is a
 one-time restore only (it stores a JSON-inferred object the first time, which core's type guard then
 refuses to re-set from a string); the simplest robust pattern is a fresh Chat element per session. readOnly
 makes it a pure viewer (no composer, no transport). Persistence flows the other way:
 entryActionID fires per finalized transcript entry with that entry's JSON, so the host stores incrementally
 as the conversation happens (keep the handler inexpensive - usage / plan updates can fire several times per
 turn). Session identity (ids, titles) stays app-side; the component only passes the optional title through
 untouched. `properties.content` pre-populates a transcript for previews / basic internal testing only - it
 is NOT the production restore path.
 Appending ONE item: states["append"] takes a single serialized ChatItem and adds it to the END of the
 conversation already on screen. states["content"] cannot serve this - it REPLACES the transcript and
 re-primes the agent - so a host with one line to add (a session marker naming the model about to answer)
 otherwise had to choose between re-priming the whole conversation and not showing it until the next load.
 Setting this state appends and nothing else: no transport traffic, no re-prime. Like states["content"] it
 does NOT come back through entryActionID - the host is telling the element about an item it already has,
 and a host that also persists would write it twice. Appending a MESSAGE (rather than a marker) puts a line
 on screen the agent was never given, so the element reports its context as pending and the next send
 re-primes. Example: setElementState(window, chatID, "append",
 {"type":"sessionEvent","sessionEvent":{"id":"se-1","kind":"resumed","model":"Qwen3 4B"}}).
 Leading the NEXT message: states["lead"] takes serialized ChatItems - one per line - and HOLDS them until
 the user sends, then places them in front of that message. states["append"] cannot serve this: a host
 learns a message exists only when its entry finalizes, by which time the message has been on screen since
 the user pressed Return, so appending puts the line meant to introduce it underneath it. The waiting is
 half the point - a conversation the user opened and read is not a conversation resumed, so a marker shown
 when the transcript was merely displayed announces a handover that never happened. The value is the WHOLE
 waiting list, so set it again (with every line) to add one, and set it to "" to take the lines back when
 the conversation they belong to is replaced (an empty array, or text with no lines in it, withdraws the
 same way; a value NONE of whose lines decode is not obeyed as a withdrawal and leaves the list as it was);
 a line already placed is never placed again, whatever the channel goes on resting on. The lines fire no entry of their own, but the MESSAGE they lead reports them:
 its entryActionID envelope carries them under "lead", as placed - and a line handed over without a
 timestamp is stamped with the moment it is placed, because the host hands it over when it learns the line
 will be needed, which can be an hour before the user types, while the line says what happened when the
 message was sent. A host that stamps its lines keeps its stamps; a host that does not records the line from
 the message's entry. Example: setElementState(window, chatID, "lead",
 "{\"type\":\"sessionEvent\",\"sessionEvent\":{\"id\":\"se-1\",\"kind\":\"resumed\",\"model\":\"Qwen3 4B\"}}").
 Host-injected transport (NOT document-declared): the non-visual settings (protocol, transport) are
 injected at runtime into states["config"] via setElementState / setElementStateFromString (e.g. OMC's
 omc_set_state) AFTER the element is built - the same seam as states["content"] restore. The element
 stays inert (no transport, composer disabled) until states["config"] first resolves to a VIABLE
 transport; then the transport is built ONCE and FROZEN, so a later states["config"] change has no
 effect on that element (create a new Chat element to switch transport). Keeping the wire protocol and
 the subprocess-spawning transport command out of the document is the security boundary - a document is
 data and must not name what the host executes or connects to. Example injection:
 setElementState(window, chatID, "config", {"protocol":"openai-sse","transport":{"baseURL":"http://127.0.0.1:8080/v1"}}).
 Inject the COMPLETE {protocol, transport} exactly once: the first VIABLE config freezes the element,
 and a config dict with no "protocol" key defaults to "local" (which is always viable), so a partial
 config injected before the real one would lock the element to "local". Deferral (waiting for a
 completer config) applies only to a registered protocol whose transport init fails on incomplete
 settings - e.g. openai-sse before its baseURL, or acp before its command.

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.

 Implementation note: the "Chat" element is a thin wrapper over the standalone ChatView package
 (a sibling repo): the component owns the transcript, store, transports, and views; this module
 conforms it to ActionUI's public ActionUIViewConstruction contract, maps the element's JSON
 properties to the component's ChatConfiguration, adapts the logger, exposes states["content"] /
 states["config"] to the component through ChatContentSource, and routes the component's host
 events (ChatHostEvent) to the configured action IDs. The type and its witnesses are internal -
 an internal type conforming to a public protocol keeps internal witnesses. The module's public
 surface is small: ActionUIChatCore.register() (element + registry logger wiring),
 registerTransport(_:factory:), and - re-exported from ChatView - the frozen transport contract
 a transport module builds against (ChatTransport, ChatEvent, ChatCommand, ChatTransportConfig,
 ChatLogger, and the value types those carry). The umbrella ActionUIChat.register() registers
 the element and every bundled transport in one call.
 */

import SwiftUI
import ActionUI

struct Chat: ActionUIViewConstruction {

    // The element has no single scalar value: its session transcript is CONTENT, restored at runtime
    // into states["content"] (like Table / List content), not carried on the element value. So the
    // value type stays Void, mirroring container-style elements.
    static var valueType: Any.Type = Void.self

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        ChatConfig.validate(properties, logger)
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        // The Chat element's operational config (protocol + transport) is NOT read here and is NOT
        // document-declared: a host injects it at runtime into states["config"], which the component's
        // store observes (through ChatContentSource) and uses to build the transport once it is viable
        // (a CHANGED viable config later re-configures in place; an identical one is deduped).
        // buildView parses only the visual/behavioral `properties`, derives the host event sink from
        // the configured action IDs, and hands `model` to the component as the content/config source.
        let chatLogger = ChatLoggerAdapter(base: logger)
        let config = ChatConfig(properties: properties, logger: chatLogger)
        let sink = Self.hostEventSink(config: config, windowUUID: windowUUID, elementID: element.id)
        return ChatView(configuration: config.configuration, logger: chatLogger,
                        contentSource: model, hostEvents: sink)
    }

    /// Maps component host events to the configured ActionUI action IDs. A named internal
    /// static function (rather than an inline closure) so the add-on test suite can
    /// exercise the dispatch mapping directly.
    static func hostEventSink(config: ChatConfig, windowUUID: String, elementID: Int) -> ChatHostEventSink {
        return { event in
            let actionID: String?
            var context: Any? = nil
            switch event {
            case .send:
                actionID = config.sendActionID
            case .stop:
                actionID = config.stopActionID
            case .attach:
                actionID = config.attachActionID
            case .messageFinalized:
                actionID = config.messageActionID
            case .error:
                actionID = config.errorActionID
            case .toolApprovalRequested:
                actionID = config.approveToolActionID
            case .entry(let json):
                actionID = config.entryActionID
                context = json
            case .resumeCheckpoint(let json):
                // The cursor that pairs with .entry - `{"afterSeq":<int>,"sessionId":"<id>"}`, emitted only
                // at turn boundaries. A host must persist it ATOMICALLY with the entries it has stored:
                // a cursor newer than its transcript silently loses everything in between, an older one
                // duplicates it. Storing neither half is safe (the transport replays the whole session).
                actionID = config.resumeCheckpointActionID
                context = json
            }
            guard let actionID, !actionID.isEmpty else {
                return
            }
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: context)
        }
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
