// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// ToolsDocuments.swift - tools for agent-authored documents and live windows: show_document,
// validate_document, wait, update_window, get_values, plus pick_path.

import Foundation
import MCPStdio

private let documentProperty: JSONValue = [
    "type": "object",
    "description": "ActionUI root element, the same format as an ActionUI .json file: {\"type\": \"VStack\", \"properties\": {...}, \"children\": [...]}. Give every element whose value you want back a unique positive integer \"id\". Pass it as an object, never as a string.",
]
private let pathProperty: JSONValue = [
    "type": "string",
    "description": "Instead of document: absolute path of an ActionUI .json file.",
]
private let windowProperty: JSONValue = ["type": "string", "description": "Window id returned by show or show_document."]

// MARK: - show_document

func showDocumentTool(host: WindowHost, label: String?) -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "document": documentProperty,
            "path": pathProperty,
            "title": ["type": "string", "description": "Window title."],
            "mode": ["type": "string", "enum": ["window", "dialog"],
                     "description": "window (default): returns {window} at once; the window's actions are queued for wait. dialog: adds a footer and a button row, waits for the user, and returns {action, button, values}."],
            "buttons": ["type": "array", "items": ["type": "string"],
                        "description": "dialog mode: button titles, left to right; the last is the default (Return); \"Cancel\" is bound to Escape. Default [\"Cancel\", \"OK\"]; [] for none (then give close_actions)."],
            "close_actions": ["type": "array", "items": ["type": "string"],
                              "description": "dialog mode: actionIDs of your own buttons that end the dialog with action \"accept\"."],
            "width": ["type": "number", "description": "Content width in points. Default: the document's own size."],
            "height": ["type": "number", "description": "Content height in points. With width, fixes the window size."],
            "timeout_s": ["type": "number", "description": "dialog mode: seconds before action \"timeout\". Default 3600."],
        ],
        "required": ["title"],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "show_document",
        title: "Show an ActionUI document",
        description: """
            Open a native window from an ActionUI document you wrote. Load errors come back as a tool \
            error and nothing is shown; call validate_document first. mode "dialog" waits for the user \
            and returns {action, button, close_action?, values}, where values maps each element id to \
            its current value. mode "window" returns {window} at once; collect the user's actions with \
            wait, change values with update_window. Results include ActionUI's warnings, if any. \
            SecureField is not allowed: everything the user enters is sent to you.
            """,
        inputSchema: input,
        annotations: ["readOnlyHint": true, "openWorldHint": false],
        heartbeatInterval: 15
    ) { arguments, context in
        let document = try AgentDocument(arguments: arguments)
        guard let title = arguments["title"]?.string, !title.isEmpty else {
            throw MCPToolError("'title' is required and must be a non-empty string")
        }
        let mode = arguments["mode"]?.string ?? "window"
        guard mode == "window" || mode == "dialog" else { throw MCPToolError("'mode' must be window or dialog") }
        var size: NSSize?
        if let width = arguments["width"]?.double, let height = arguments["height"]?.double {
            size = NSSize(width: min(max(width, 160), 3000), height: min(max(height, 80), 3000))
        }
        try await requireGraphicalSession(host)
        let subtitle = provenance(clientName: context.clientName, label: label)
        try Task.checkCancellation()

        if mode == "window" {
            // A width alone sizes the content; the height then follows from it.
            var root = document.root
            if size == nil, let width = arguments["width"]?.double {
                root = ["type": "VStack", "properties": ["frame": ["width": .double(min(max(width, 160), 3000))]], "children": [root]]
            }
            let sizing: WindowHost.Sizing = size.map { .fixed($0) } ?? .fitting(resizable: true)
            let opened = try await MainActor.run { [root] in
                try host.openWindow(document: root.any as? [String: Any] ?? [:], title: title, subtitle: subtitle,
                                    sizing: sizing, activate: false, queuesEvents: true, rejectLoadErrors: true)
            }
            var result: [String: JSONValue] = ["window": .string(opened.id)]
            let warnings = document.warnings + opened.warnings
            if !warnings.isEmpty { result["warnings"] = .array(warnings.map(JSONValue.string)) }
            return .structured(.object(result))
        }

        let dialog = try DocumentDialog(arguments: arguments)
        let timeout = min(max(arguments["timeout_s"]?.double ?? defaultDialogTimeout, 1), maxDialogTimeout)
        let opened = try await host.beginDocumentDialog(document: document, dialog: dialog, title: title,
                                                        subtitle: subtitle, size: size, timeout: timeout)
        guard case .object(var result) = await host.result(of: opened.id) else {
            throw MCPToolError("internal error: dialog result is not an object")
        }
        let warnings = document.warnings + opened.warnings
        if !warnings.isEmpty { result["warnings"] = .array(warnings.map(JSONValue.string)) }
        return .structured(.object(result))
    }
}

// MARK: - validate_document

func validateDocumentTool(host: WindowHost) -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": ["document": documentProperty, "path": pathProperty],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "validate_document",
        title: "Check an ActionUI document",
        description: """
            Check an ActionUI document without showing it: structure (element shape, unique positive \
            ids, container keys such as children placed next to properties), disallowed elements, and \
            ActionUI's own load errors and warnings. Returns {ok, errors, warnings}. Unknown property \
            names are not detected yet; the actionui skill's verifier catches those.
            """,
        inputSchema: input,
        outputSchema: ["type": "object",
                       "properties": ["ok": ["type": "boolean"],
                                      "errors": ["type": "array", "items": ["type": "string"]],
                                      "warnings": ["type": "array", "items": ["type": "string"]]],
                       "required": ["ok", "errors", "warnings"]],
        annotations: ["readOnlyHint": true, "openWorldHint": false]
    ) { arguments, _ in
        let document: AgentDocument
        do {
            document = try AgentDocument(arguments: arguments)
        } catch let error as MCPToolError {
            // Structural errors are the answer, not a failure of the tool.
            let lines = error.message.split(separator: "\n").map(String.init)
            let errors = lines.first?.hasSuffix("errors:") == true ? Array(lines.dropFirst()) : lines
            return .structured(["ok": false, "errors": .array(errors.map(JSONValue.string)), "warnings": []])
        }
        let loaded = try await MainActor.run { try host.check(document: document.foundation) }
        let warnings = document.warnings + loaded.warnings
        return .structured(["ok": .bool(loaded.errors.isEmpty),
                            "errors": .array(loaded.errors.prefix(50).map(JSONValue.string)),
                            "warnings": .array(warnings.prefix(50).map(JSONValue.string))])
    }
}

// MARK: - wait

func waitTool(host: WindowHost) -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "window": ["type": "string", "description": "Window id; omit to wait on every window that sends events."],
            "timeout_s": ["type": "number", "description": "Seconds to wait when nothing is queued yet. Default 300, at most 3600."],
        ],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "wait",
        title: "Wait for window events",
        description: """
            Return the user's actions in windows opened by show_document in window mode, \
            waiting until at least one arrives or the timeout passes. Returns {events, dropped} with \
            events [{window, action, id?, value?, count?, at}] oldest first; repeated actions on one \
            element are merged into the latest with a count. When the user closes a window its last \
            event has action "window.closed". Each call is one round trip, so act on the whole batch \
            before waiting again.
            """,
        inputSchema: input,
        annotations: ["readOnlyHint": true, "openWorldHint": false],
        heartbeatInterval: 15
    ) { arguments, _ in
        let timeout = min(max(arguments["timeout_s"]?.double ?? 300, 0), 3600)
        return .structured(try await host.waitForEvents(window: arguments["window"]?.string, timeout: timeout))
    }
}

// MARK: - update_window, get_values

func updateWindowTool(host: WindowHost) -> MCPTool {
    let byID: JSONValue = ["type": "object", "additionalProperties": ["type": "array", "items": ["type": "array"]]]
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "window": windowProperty,
            "values": ["type": "object", "description": "Element id to new value (string, number, or boolean), for example {\"3\": \"Done\", \"4\": 0.75}."],
            "rows": byID.merging(description: "Table or List id to its new rows, each an array of cells; replaces all rows."),
            "append_rows": byID.merging(description: "Table or List id to rows to add at the end."),
        ],
        "required": ["window"],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "update_window",
        title: "Change values in a window",
        description: "Set element values and table rows in an open window, for example to update a progress view while you work. Returns {updated, problems}.",
        inputSchema: input,
        annotations: ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]
    ) { arguments, _ in
        guard let windowID = arguments["window"]?.string else { throw MCPToolError("'window' is required") }
        let values = arguments["values"]?.object ?? [:]
        let rows = arguments["rows"]?.object ?? [:]
        let appendRows = arguments["append_rows"]?.object ?? [:]
        let problems = try await host.update(windowID: windowID, values: values, rows: rows, appendRows: appendRows)
        let attempted = values.count + rows.count + appendRows.count
        return .structured(["updated": .int(attempted - problems.count), "problems": .array(problems.map(JSONValue.string))])
    }
}

func getValuesTool(host: WindowHost) -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "window": windowProperty,
            "ids": ["type": "array", "items": ["type": "integer"], "description": "Element ids; omit for every element with an id."],
        ],
        "required": ["window"],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "get_values",
        title: "Read values from a window",
        description: "Read the current values of elements in an open window. Returns {values} mapping element id to value; elements without a value are left out.",
        inputSchema: input,
        annotations: ["readOnlyHint": true, "openWorldHint": false]
    ) { arguments, _ in
        guard let windowID = arguments["window"]?.string else { throw MCPToolError("'window' is required") }
        let ids = arguments["ids"]?.array.map { $0.compactMap { $0.double.flatMap { Int(exactly: $0) } } }
        let values = try await MainActor.run {
            try host.requireWindow(windowID)
            return host.values(windowID: windowID, ids: ids)
        }
        return .structured(["values": .object(values)])
    }
}

// MARK: - pick_path

func pickPathTool(host: WindowHost) -> MCPTool {
    let input: JSONValue = [
        "type": "object",
        "properties": [
            "kind": ["type": "string", "enum": ["file", "folder", "save"],
                     "description": "file (default) or folder to open an existing item; save to choose a new file's location and name."],
            "title": ["type": "string", "description": "Panel title."],
            "message": ["type": "string", "description": "Text shown in the panel: what to pick and why."],
            "allowed_types": ["type": "array", "items": ["type": "string"],
                              "description": "File extensions (\"pdf\") or type identifiers (\"public.image\")."],
            "multiple": ["type": "boolean", "description": "kind file or folder: allow several."],
            "directory": ["type": "string", "description": "Absolute path of the folder to start in."],
            "default_name": ["type": "string", "description": "kind save: suggested file name."],
            "timeout_s": ["type": "number", "description": "Seconds before action \"timeout\". Default 3600."],
        ],
        "additionalProperties": false,
    ]
    return MCPTool(
        name: "pick_path",
        title: "Pick a file or folder",
        description: """
            Show the macOS open or save panel and wait for the user. Returns {action, paths}: action \
            "accept" with absolute paths, "cancel", or "timeout". A save path is only chosen, not \
            created. Blocks until the user answers; some clients move a long call to the background.
            """,
        inputSchema: input,
        outputSchema: ["type": "object",
                       "properties": ["action": ["type": "string", "enum": ["accept", "cancel", "timeout"]],
                                      "paths": ["type": "array", "items": ["type": "string"]]],
                       "required": ["action", "paths"]],
        annotations: ["readOnlyHint": true, "openWorldHint": false],
        heartbeatInterval: 15
    ) { arguments, _ in
        let spec = try PanelSpec(arguments: arguments)
        let timeout = min(max(arguments["timeout_s"]?.double ?? defaultDialogTimeout, 1), maxDialogTimeout)
        try await requireGraphicalSession(host)
        try Task.checkCancellation()
        return .structured(await host.pickPath(spec, timeout: timeout))
    }
}

private extension JSONValue {
    func merging(description: String) -> JSONValue {
        guard case .object(var object) = self else { return self }
        object["description"] = .string(description)
        return .object(object)
    }
}
