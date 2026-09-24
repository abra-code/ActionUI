// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Tools.swift - the tool surface of the proof of concept: ask_user (blocking), show and
// close_window (non-blocking). Definitions and handlers side by side; handlers parse arguments off
// the main actor and hop to it for anything that touches a window.

import Foundation
import MCPStdio

/// Seconds a dialog waits by default before answering "timeout", and the most a call may ask for.
let defaultDialogTimeout = 3600.0
let maxDialogTimeout = 86400.0

func makeTools(host: WindowHost, label: String?) -> [MCPTool] {
    [askUserTool(host: host, label: label), pickPathTool(host: host),
     showTool(host: host, label: label), showDocumentTool(host: host, label: label), validateDocumentTool(host: host),
     waitTool(host: host), updateWindowTool(host: host), getValuesTool(host: host), screenshotTool(host: host),
     closeWindowTool(host: host)]
}

/// "Requested by <client> - <label>": shown in every window's title bar, not settable by a tool.
func provenance(clientName: String?, label: String?) -> String {
    var text = "Requested by " + (clientName ?? "an AI agent")
    if let label, !label.isEmpty { text += " - " + label }
    return text
}

func requireGraphicalSession(_ host: WindowHost) async throws {
    guard await host.hasGraphicalSession else {
        throw MCPToolError("no graphical session: windows cannot be shown on this machine right now (remote or SSH session?)")
    }
}

// MARK: - ask_user

private func askUserTool(host: WindowHost, label: String?) -> MCPTool {
    let kinds = JSONValue.array(FieldKind.allCases.map { .string($0.rawValue) })
    let field: JSONValue = [
        "type": "object",
        "properties": [
            "key": ["type": "string", "description": "Name of this answer in the returned values."],
            "label": ["type": "string", "description": "Label shown to the user; defaults to key."],
            "kind": ["type": "string", "enum": kinds,
                     "description": "text (one line), multiline, number, integer, toggle (true/false), choice (one of options), slider (number in min...max), date (YYYY-MM-DD). Default text."],
            "default": ["description": "Initial value: string, number, or boolean matching kind."],
            "required": ["type": "boolean", "description": "The user cannot accept while this is empty."],
            "placeholder": ["type": "string", "description": "Hint text for text, multiline, number, integer."],
            "options": ["type": "array", "description": "For choice: strings, or {value, label} objects.",
                        "items": ["anyOf": [["type": "string"],
                                            ["type": "object",
                                             "properties": ["value": ["type": "string"], "label": ["type": "string"]],
                                             "required": ["value"], "additionalProperties": false]]]],
            "min": ["type": "number", "description": "For slider."],
            "max": ["type": "number", "description": "For slider."],
            "step": ["type": "number", "description": "For slider."],
        ],
        "required": ["key"],
        "additionalProperties": false,
    ]
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "title": ["type": "string", "description": "Window title: what is being asked, in a few words."],
            "message": ["type": "string", "description": "Question or explanation shown above the fields. Markdown allowed."],
            "fields": ["type": "array", "items": field, "description": "Input fields, top to bottom, at most 30. Omit for a plain confirmation."],
            "buttons": ["type": "array", "items": ["type": "string"],
                        "description": "Button titles, left to right. The last one is the default (Return). A button titled \"Cancel\" is bound to Escape and answers action \"cancel\". Default [\"Cancel\", \"OK\"]."],
            "width": ["type": "number", "description": "Dialog width in points, 320 to 1000. Default 460."],
            "timeout_s": ["type": "number", "description": "Seconds to wait before answering action \"timeout\". Default 3600."],
        ],
        "required": ["title"],
        "additionalProperties": false,
    ]
    let output: JSONValue = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["accept", "cancel", "timeout"]],
            "button": ["type": ["string", "null"], "description": "Title of the button pressed; null when the window was closed or timed out."],
            "values": ["type": "object", "description": "Present only for accept: field key to value."],
        ],
        "required": ["action", "button"],
    ]
    return MCPTool(
        name: "ask_user",
        title: "Ask the user",
        description: """
            Show a native macOS dialog with a message, optional input fields, and buttons, and wait \
            until the user answers. Returns {action, button, values}: action "accept" with the pressed \
            button and every field's value; "cancel" when the user pressed Cancel or closed the window; \
            "timeout". Use for questions that need the user's input or approval before you continue. \
            Blocks until the user answers; some clients move a long-running call to the background and \
            deliver the answer later. Do not ask for passwords or other secrets: answers are sent to you.
            """,
        inputSchema: input,
        outputSchema: output,
        annotations: ["readOnlyHint": true, "openWorldHint": false],
        heartbeatInterval: 15
    ) { arguments, context in
        let spec = try DialogSpec(arguments: arguments)
        let timeout = min(max(arguments["timeout_s"]?.double ?? defaultDialogTimeout, 1), maxDialogTimeout)
        try await requireGraphicalSession(host)
        let subtitle = provenance(clientName: context.clientName, label: label)
        // A call cancelled while it was being parsed must not flash a dialog on screen.
        try Task.checkCancellation()
        let windowID = try await host.beginDialog(spec: spec, subtitle: subtitle, timeout: timeout)
        return .structured(await host.result(of: windowID))
    }
}

// MARK: - show

private func showTool(host: WindowHost, label: String?) -> MCPTool {
    let kinds = JSONValue.array(ContentKind.allCases.map { .string($0.rawValue) })
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "title": ["type": "string", "description": "Window title."],
            "kind": ["type": "string", "enum": kinds,
                     "description": "markdown (text), text (plain monospaced text), image (path or url), pdf or file (path; anything Quick Look previews), video (path or url), web (url, or HTML in text), diff (old_text or old_path against new_text or new_path), table (columns and rows)."],
            "text": ["type": "string", "description": "Content for markdown, text, and web (HTML)."],
            "path": ["type": "string", "description": "Absolute path of a local file for image, pdf, file, video."],
            "url": ["type": "string", "description": "http(s) URL for image, video, web."],
            "old_text": ["type": "string", "description": "For diff: the old (left) text."],
            "new_text": ["type": "string", "description": "For diff: the new (right) text."],
            "old_path": ["type": "string", "description": "For diff: absolute path of the old file, instead of old_text."],
            "new_path": ["type": "string", "description": "For diff: absolute path of the new file, instead of new_text."],
            "columns": ["type": "array", "items": ["type": "string"], "description": "For table: column headers."],
            "rows": ["type": "array", "description": "For table: rows, each an array of cells (strings or numbers), at most one per column.",
                     "items": ["type": "array", "items": ["type": ["string", "number", "boolean", "null"]]]],
            "width": ["type": "number", "description": "Content width in points. Default 800."],
            "height": ["type": "number", "description": "Content height in points. Default 600."],
        ],
        "required": ["title", "kind"],
        "additionalProperties": false,
    ]
    let output: JSONValue = [
        "type": "object",
        "properties": ["window": ["type": "string", "description": "Window id for close_window."]],
        "required": ["window"],
    ]
    return MCPTool(
        name: "show",
        title: "Show content in a window",
        description: """
            Open a native macOS window that presents content to the user: a markdown report, plain \
            text, an image, a PDF or any file Quick Look can preview, a video, a web page, a diff of two \
            texts or files, or a table. Returns \
            {window} at once without waiting; the window stays open until the user closes it, you call \
            close_window, or this session ends. It does not take keyboard focus.
            """,
        inputSchema: input,
        outputSchema: output,
        annotations: ["readOnlyHint": true, "openWorldHint": false]
    ) { arguments, context in
        let spec = try ViewerSpec(arguments: arguments)
        try await requireGraphicalSession(host)
        let subtitle = provenance(clientName: context.clientName, label: label)
        let windowID = try await host.openViewer(spec: spec, subtitle: subtitle)
        return .structured(["window": .string(windowID)])
    }
}

// MARK: - close_window

private func closeWindowTool(host: WindowHost) -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": ["window": ["type": "string", "description": "Window id returned by show."]],
        "required": ["window"],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "close_window",
        title: "Close a window",
        description: "Close a window opened by show. Returns {closed}: false when the user already closed it. Closing a waiting ask_user dialog answers it with action \"cancel\".",
        inputSchema: input,
        outputSchema: ["type": "object", "properties": ["closed": ["type": "boolean"]], "required": ["closed"]],
        annotations: ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
    ) { arguments, _ in
        guard let windowID = arguments["window"]?.string else { throw MCPToolError("'window' is required") }
        let closed = await host.closeWindow(windowID)
        return .structured(["closed": .bool(closed)])
    }
}
