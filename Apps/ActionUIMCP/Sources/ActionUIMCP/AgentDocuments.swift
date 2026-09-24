// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AgentDocuments.swift - ActionUI documents written by the agent (show_document,
// validate_document). A document arrives as a JSON object nested in the tool arguments, or as an
// absolute path to a .json file, never as a string. Before anything loads it gets structural
// checks for the mistakes ActionUI's loader would silently ignore, and the safety rules of the
// design: no SecureField (every answer reaches the model), no WebView user scripts.

import Foundation
import MCPStdio

struct AgentDocument {
    /// The checked document (always an element object). Sendable, so it can cross to the main
    /// actor; `foundation` converts it for loading there.
    let root: JSONValue
    /// Problems that do not stop the document from loading.
    let warnings: [String]

    static let maxBytes = 4 * 1024 * 1024
    /// Keys that hold child elements. They belong next to "properties", never inside it.
    private static let containerKeys = ["children", "content", "destinations", "template", "rows",
                                        "sheet", "popover", "fullScreenCover", "overlay", "toolbar"]
    /// Every key ActionUI reads child elements from (ActionUIElement's decoder), so the safety
    /// rules reach elements nested anywhere. Some of these ("label", "background") are also
    /// property names, so they are not in `containerKeys`.
    private static let childArrayKeys = ["children", "destinations", "toolbar", "persistentToolbar", "commands",
                                         "contextMenu", "swipeActions"]
    private static let childKeys = ["content", "destination", "sidebar", "detail", "label", "popover", "template",
                                    "sheet", "fullScreenCover", "overlay", "background", "contextMenuPreview",
                                    "safeAreaInset"]
    private static let allowSecureFields = ProcessInfo.processInfo.environment["ACTIONUI_MCP_ALLOW_SECURE_FIELDS"] == "1"

    /// Reads `document` (object) or `path` (absolute .json file) from the arguments and checks it.
    /// Throws MCPToolError listing every structural error found.
    init(arguments: [String: JSONValue]) throws {
        let value: JSONValue
        if let document = arguments["document"], document != .null {
            guard case .object = document else {
                throw MCPToolError("'document' must be an ActionUI element object such as {\"type\": \"VStack\", ...}, not a string")
            }
            guard document.serialized().utf8.count <= Self.maxBytes else {
                throw MCPToolError("the document is larger than \(Self.maxBytes / 1024 / 1024) MB")
            }
            value = document
        } else if let path = arguments["path"]?.string {
            value = try Self.load(path: path)
        } else {
            throw MCPToolError("give the ActionUI document as 'document' (an object) or 'path' (an absolute .json path)")
        }

        var errors: [String] = []
        var warnings: [String] = []
        var ids: Set<Int> = []
        let checked = Self.check(value, at: "root", errors: &errors, warnings: &warnings, ids: &ids)
        // Then the ActionUIVerifier checks: element types, property names, value types, enums,
        // required properties, platform rules. Its errors refuse the document; its warnings go
        // back with the result.
        if errors.isEmpty {
            if let validator = Verifier.validator {
                for issue in validator.validate(jsonObject: checked.any, rootPath: "root") {
                    switch issue.severity {
                    case .error: errors.append("\(issue.path): \(issue.message)")
                    case .warning: warnings.append("\(issue.path): \(issue.message)")
                    default: break
                    }
                }
            } else {
                warnings.append(Verifier.unavailableWarning)
            }
        }
        if !errors.isEmpty {
            let shown = errors.prefix(20).joined(separator: "\n")
            let more = errors.count > 20 ? "\n... and \(errors.count - 20) more" : ""
            throw MCPToolError("the document has errors:\n" + shown + more)
        }
        self.root = checked
        self.warnings = warnings
    }

    /// The document in the Foundation form ActionUI loads.
    var foundation: [String: Any] {
        root.any as? [String: Any] ?? [:]
    }

    private static func load(path: String) throws -> JSONValue {
        guard path.hasPrefix("/") else { throw MCPToolError("'path' must be absolute: \(path)") }
        guard path.lowercased().hasSuffix(".json") else { throw MCPToolError("'path' must name a .json file: \(path)") }
        let url = URL(fileURLWithPath: path)
        // The size of the file a symlink points to, not of the link.
        let resolved = url.resolvingSymlinksInPath().path
        let size = (try? FileManager.default.attributesOfItem(atPath: resolved)[.size] as? Int) ?? nil
        guard let size else { throw MCPToolError("no such file: \(path)") }
        guard size <= maxBytes else { throw MCPToolError("\(path) is larger than \(maxBytes / 1024 / 1024) MB") }
        do {
            let data = try Data(contentsOf: url)
            return JSONValue(any: try JSONSerialization.jsonObject(with: data))
        } catch {
            throw MCPToolError("\(path) is not valid JSON: \(error.localizedDescription)")
        }
    }

    /// Checks one element and its children, returning it with unsafe parts removed.
    private static func check(_ node: JSONValue, at location: String, errors: inout [String],
                              warnings: inout [String], ids: inout Set<Int>) -> JSONValue {
        guard var object = node.object else {
            errors.append("\(location): an element must be an object")
            return node
        }
        guard let type = object["type"]?.string, !type.isEmpty else {
            errors.append("\(location): missing \"type\"")
            return node
        }
        let here = "\(location) (\(type))"
        if let id = object["id"] {
            if case .int(let number) = id, number > 0 {
                if !ids.insert(number).inserted { errors.append("\(here): id \(number) is used more than once") }
            } else {
                errors.append("\(here): \"id\" must be a positive integer")
            }
        }
        if var properties = object["properties"]?.object {
            for key in containerKeys where properties[key] != nil {
                errors.append("\(here): \"\(key)\" must be a key of the element, next to \"properties\", not inside it")
            }
            if type == "WebView", properties["userScripts"] != nil {
                properties["userScripts"] = nil
                object["properties"] = .object(properties)
                warnings.append("\(here): userScripts removed; scripts from an agent are not run")
            }
        } else if object["properties"] != nil {
            errors.append("\(here): \"properties\" must be an object")
        }
        if type == "SecureField" && !allowSecureFields {
            errors.append("\(here): SecureField is not allowed; whatever the user types is sent to the AI agent")
        }
        // Recurse into every child slot whose shape matches; anything else is left to the loader.
        func checkItems(_ items: [JSONValue], at path: String) -> [JSONValue] {
            items.enumerated().map { index, item in
                item.object != nil
                    ? check(item, at: "\(path)[\(index)]", errors: &errors, warnings: &warnings, ids: &ids)
                    : item
            }
        }
        for key in childArrayKeys {
            if case .array(let items) = object[key] { object[key] = .array(checkItems(items, at: "\(location).\(key)")) }
        }
        // Grid rows: an array of rows, each an array of cells.
        if case .array(let rows) = object["rows"] {
            object["rows"] = .array(rows.enumerated().map { index, row in
                row.array.map { .array(checkItems($0, at: "\(location).rows[\(index)]")) } ?? row
            })
        }
        for key in childKeys {
            if case .object = object[key] {
                object[key] = check(object[key]!, at: "\(location).\(key)", errors: &errors, warnings: &warnings, ids: &ids)
            }
        }
        return .object(object)
    }
}

/// Standard dialog chrome around an agent document: the document, the footer, and a button row.
struct DocumentDialog {
    let buttons: [DialogButton]
    /// actionIDs in the document that end the dialog, for agents that draw their own buttons.
    let closeActions: Set<String>
    let width: Double?

    init(arguments: [String: JSONValue]) throws {
        buttons = try DialogSpec.parseButtons(arguments["buttons"], allowEmpty: true)
        let actions = (arguments["close_actions"]?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        if let reserved = actions.first(where: { $0.hasPrefix("mcp.") }) {
            throw MCPToolError("close_actions must not start with \"mcp.\" (reserved): \(reserved)")
        }
        closeActions = Set(actions)
        guard !buttons.isEmpty || !closeActions.isEmpty else {
            throw MCPToolError("a dialog needs 'buttons' or 'close_actions', or the user could only close the window")
        }
        width = arguments["width"]?.double.map { min(max($0, 240), 3000) }
    }

    func wrap(_ document: [String: Any], footer: String) -> [String: Any] {
        var children: [[String: Any]] = [
            document,
            ["type": "Text", "properties": ["text": footer, "font": "caption", "foregroundStyle": "secondary",
                                            "frame": ["maxWidth": "infinity", "alignment": "leading"]]],
        ]
        if !buttons.isEmpty { children.append(DialogSpec.buttonRow(buttons)) }
        var properties: [String: Any] = ["alignment": "leading", "spacing": 14, "padding": 20]
        if let width { properties["frame"] = ["width": width] }
        return ["type": "VStack", "properties": properties, "children": children]
    }
}
