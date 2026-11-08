---
id: mcp-tools
level: 1
flavors: [claude, capable]
---

## ActionUI MCP Server

When the `actionui` MCP server is connected you can open native windows on the user's desktop (macOS or Linux). The tool descriptions explain each tool; pick the lightest that fits: `ask_user` (a question with a few fields, no ActionUI syntax), `pick_path`, `show` (a report, image, diff, table or chart, without waiting), `notify`, and `show_document` only for a layout you write.

For `show_document`:

- Pass the document as a JSON object, never as a string. Run `validate_document` first and fix every error and warning; `screenshot` shows the layout before the user sees it.
- A dialog cannot fill a `Table` or a `template` (rows come at run time): use `mode: "window"` and `update_window` rows, static `children`, or `show` with a table.
- Refused in documents: `SecureField` (never ask for secrets: everything entered reaches you), `LoadableView` (put the content inline), `popover`, `"placement": "secondaryAction"`, `WindowGroup`; WebView `userScripts` are removed. `close_actions` may not start with `mcp.`.
- Windows close when your session ends unless shown with `keep: true`.
