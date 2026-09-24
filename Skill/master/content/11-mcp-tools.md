---
id: mcp-tools
level: 1
flavors: [claude, capable]
---

## ActionUI MCP Server Tools

When the `actionui` MCP server is connected, you can put native windows on the user's Mac directly. Pick the lightest tool that fits:

| Need | Tool |
|------|------|
| A question, choice, or approval with a few typed fields | `ask_user` - no ActionUI syntax; returns `{action, button, values}` |
| Several options at once | `ask_user` with a `multichoice` field (checkboxes; the answer is an array) |
| A file, folder, or save location | `pick_path` |
| Show a report, text, image, PDF, video, web page, diff, or table and move on | `show` - returns at once |
| Tell the user something short, such as a finished job, without interrupting | `notify` - disappears by itself |
| Any other layout | `show_document` with a document you write |

**Documents.** Pass the document as a JSON object in the `document` argument (or an absolute `.json` path in `path`), never as a string. Give every element whose value you need a unique positive `id`. Run `validate_document` first: fix every error, and read the warnings, which usually name a misspelled property. `show_document` refuses a document with errors, and returns any warnings with its result. To see the layout before the user does, `screenshot` renders the document off screen and returns a PNG.

**Dialog or window.** `mode: "dialog"` adds a footer and buttons (the last is the default; "Cancel" is bound to Escape), waits, and returns every value keyed by id. Draw your own buttons instead with `buttons: []` and list their actionIDs in `close_actions`. `mode: "window"` returns `{window}` at once: collect the user's actions with `wait`, update the window with `update_window` (values, table rows), read it with `get_values`, and end with `close_window`. Each `wait` is a round trip, so handle the whole batch it returns before waiting again.

**Keeping a window.** Windows close when your session ends. Pass `keep: true` to `show`, or to `show_document` in window mode, for content the user will want after you are done, such as a report or a diff. The window that stays is a copy with the values it had: its actions no longer reach you.

**Waiting.** Blocking calls (`ask_user`, `pick_path`, dialogs, `wait`) last until the user acts or `timeout_s` passes. Some clients move a long call to the background and deliver the result later; do not assume an answer you have not received.

**Privacy.** Everything the user enters is sent to you. Never ask for passwords or other secrets; SecureField is refused.
