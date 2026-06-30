# ActionUI.Chat

JSON schema and usage documentation for `Chat` (ActionUIChat add-on).

```jsonc
// Add-ons/ActionUIChat/Sources/Chat.swift
// JSON specification for ActionUI.Chat:
 {
   "type": "Chat",
   "id": 1,                  // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "protocol": "local",                 // Optional: transport; "local" (default) echoes a scripted reply.
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
     "transport": { "echo": true },       // Optional: protocol-specific config (validated by the chosen transport).
                                          //           "local" honors "echo" (default true: stream a demo reply).
     "sendActionID": "chat.send",         // Optional: fired when the user submits a message
     "stopActionID": "chat.stop",         // Optional: fired when the user cancels an in-flight turn
     "messageActionID": "chat.message",   // Optional: fired per finalized message (user and agent)
     "errorActionID": "chat.error"        // Optional: fired on a transport / parse error
   }
 }
// A native chat surface, implemented as an ActionUI add-on (registered via ActionUIChat.register()).
// A transcript above a composer; the transport (selected by "protocol") drives the conversation and the
// element pre-filters its stream so chat text lands in the transcript. The element is GENERIC: the same
// element backs AI-agent chat and person-to-person chat - the transport and appearance differ, not the view.
//
// M1 (this version): the "local" transport (a scripted echo backend) and a single-alignment transcript
// with plain-text streaming - append, stream deltas, finalize - plus auto-scroll. Streaming Markdown, the
// ACP transport, dual alignment, and the agentic side surfaces (tool calls, plans, permissions) arrive in
// later milestones (see Private/chat-element-design.md).
//
// Observable state: the element manages its own transcript model internally (no single scalar value), so
// it does not expose getElementValue / setElementValue in M1; host interaction is via the action IDs above.
//
// Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
// cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
```
