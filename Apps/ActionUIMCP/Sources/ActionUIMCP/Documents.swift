// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// Documents.swift - the ActionUI documents the canned tools show. The agent passes a few typed
// parameters; the server assembles the document here, so the agent never writes ActionUI syntax
// for a simple dialog or viewer.

import Foundation
import MCPStdio

// MARK: - ask_user

enum FieldKind: String, CaseIterable {
    case text, multiline, number, integer, toggle, choice, slider, date
}

struct DialogField {
    let key: String
    let label: String
    let kind: FieldKind
    let defaultValue: JSONValue?
    let required: Bool
    let placeholder: String?
    /// (tag, title) pairs for `choice`.
    let options: [(tag: String, title: String)]
    let min: Double?
    let max: Double?
    let step: Double?
    /// ActionUI view id of the field's control.
    let viewID: Int
}

struct DialogButton {
    let title: String
    let isDefault: Bool
    let isCancel: Bool
    var actionID: String
}

struct DialogSpec {
    let title: String
    let message: String?
    let fields: [DialogField]
    let buttons: [DialogButton]
    let width: Double

    static let buttonActionPrefix = "mcp.dialog.button."
    /// View ids 1... belong to fields; nothing else in a dialog carries an id.
    static let firstFieldViewID = 1

    /// Parses and checks ask_user arguments. Every problem is a message for the agent.
    init(arguments: [String: JSONValue]) throws {
        guard let title = arguments["title"]?.string, !title.isEmpty else {
            throw MCPToolError("'title' is required and must be a non-empty string")
        }
        self.title = title
        self.message = arguments["message"]?.string
        self.width = min(max(arguments["width"]?.double ?? 460, 320), 1000)

        var fields: [DialogField] = []
        var seenKeys: Set<String> = []
        for (index, raw) in (arguments["fields"]?.array ?? []).enumerated() {
            guard let object = raw.object else { throw MCPToolError("fields[\(index)] must be an object") }
            guard let key = object["key"]?.string, !key.isEmpty else {
                throw MCPToolError("fields[\(index)].key is required")
            }
            guard seenKeys.insert(key).inserted else { throw MCPToolError("duplicate field key '\(key)'") }
            let kindName = object["kind"]?.string ?? "text"
            guard let kind = FieldKind(rawValue: kindName) else {
                let known = FieldKind.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("fields[\(index)].kind '\(kindName)' is not one of: \(known)")
            }
            var options: [(tag: String, title: String)] = []
            for option in object["options"]?.array ?? [] {
                if let text = option.string {
                    options.append((text, text))
                } else if let value = option["value"]?.string {
                    options.append((value, option["label"]?.string ?? value))
                } else {
                    throw MCPToolError("fields[\(index)].options entries must be strings or {value, label}")
                }
            }
            if kind == .choice && options.isEmpty {
                throw MCPToolError("fields[\(index)] is a choice and needs 'options'")
            }
            // Otherwise the Picker would draw the first option while the agent believes its default is set.
            if kind == .choice, let initial = object["default"], initial != .null,
               !options.contains(where: { $0.tag == initial.string }) {
                throw MCPToolError("fields[\(index)].default must be one of the option values")
            }
            // ActionUI's Picker never draws an option whose tag is empty.
            if options.contains(where: { $0.tag.isEmpty }) {
                throw MCPToolError("fields[\(index)].options values must not be empty strings")
            }
            let minimum = object["min"]?.double
            let maximum = object["max"]?.double
            if kind == .slider, (minimum == nil) != (maximum == nil) {
                throw MCPToolError("fields[\(index)] is a slider: give both 'min' and 'max', or neither")
            }
            // ActionUI draws a slider with a bad range as 0...1 and one with an out-of-range value
            // clamped, while the snapshot would report the numbers given here; reject the mismatch.
            if kind == .slider, let minimum, let maximum {
                guard minimum <= maximum else {
                    throw MCPToolError("fields[\(index)] is a slider: 'min' must not exceed 'max'")
                }
                if let initial = object["default"]?.double, initial < minimum || initial > maximum {
                    throw MCPToolError("fields[\(index)].default \(initial) is outside min...max (\(minimum)...\(maximum))")
                }
            }
            fields.append(DialogField(key: key, label: object["label"]?.string ?? key, kind: kind,
                                      defaultValue: object["default"], required: object["required"]?.bool ?? false,
                                      placeholder: object["placeholder"]?.string, options: options,
                                      min: minimum, max: maximum, step: object["step"]?.double,
                                      viewID: Self.firstFieldViewID + index))
        }
        self.fields = fields

        var titles = (arguments["buttons"]?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        if titles.isEmpty { titles = ["Cancel", "OK"] }
        // Case-insensitive, like the Cancel match below: "Cancel" and "cancel" would be two Escape buttons.
        guard Set(titles.map { $0.lowercased() }).count == titles.count else {
            throw MCPToolError("button titles must be unique")
        }
        // The last button is the default (Return). A button titled Cancel is the Escape button and
        // reports action "cancel"; so does closing the window.
        let defaultIndex = titles.count - 1
        self.buttons = titles.enumerated().map { index, title in
            let isCancel = title.caseInsensitiveCompare("Cancel") == .orderedSame
            return DialogButton(title: title, isDefault: index == defaultIndex && !isCancel, isCancel: isCancel,
                                actionID: Self.buttonActionPrefix + String(index))
        }
    }

    func document(footer: String) -> [String: Any] {
        // The title is the window title; the message is the heading of the content.
        var children: [[String: Any]] = []
        if let message, !message.isEmpty {
            children.append(["type": "Text", "properties": ["markdown": message, "font": ["size": 14],
                                                           "frame": ["maxWidth": "infinity", "alignment": "leading"]]])
        }
        if !fields.isEmpty {
            children.append(["type": "Form", "children": fields.map(fieldElement)])
        }
        children.append(["type": "Text", "properties": ["text": footer, "font": "caption", "foregroundStyle": "secondary",
                                                       "frame": ["maxWidth": "infinity", "alignment": "leading"]]])
        children.append(["type": "HStack", "properties": ["spacing": 8],
                         "children": [["type": "Spacer"]] + buttons.map(buttonElement)])
        return ["type": "VStack",
                "properties": ["alignment": "leading", "spacing": 14, "padding": 20, "frame": ["width": width]],
                "children": children]
    }

    private func fieldElement(_ field: DialogField) -> [String: Any] {
        let label = field.required ? field.label + " *" : field.label
        var properties: [String: Any] = [:]
        let control: [String: Any]
        switch field.kind {
        case .text, .number, .integer:
            properties["title"] = label
            if let text = field.defaultValue.map(Self.text(of:)) { properties["text"] = text }
            if let placeholder = field.placeholder { properties["prompt"] = placeholder }
            return ["type": "TextField", "id": field.viewID, "properties": properties]
        case .multiline:
            properties["text"] = field.defaultValue.map(Self.text(of:)) ?? ""
            if let placeholder = field.placeholder { properties["placeholder"] = placeholder }
            properties["frame"] = ["minHeight": 80, "idealHeight": 120]
            control = ["type": "TextEditor", "id": field.viewID, "properties": properties]
        case .toggle:
            properties["title"] = label
            properties["isOn"] = field.defaultValue?.bool ?? false
            return ["type": "Toggle", "id": field.viewID, "properties": properties]
        case .choice:
            properties["title"] = label
            properties["options"] = field.options.map { ["title": $0.title, "tag": $0.tag] }
            properties["pickerStyle"] = field.options.count <= 4 ? "radioGroup" : "menu"
            return ["type": "Picker", "id": field.viewID, "properties": properties]
        case .slider:
            properties["value"] = field.defaultValue?.double ?? field.min ?? 0
            if let min = field.min, let max = field.max { properties["range"] = ["min": min, "max": max] }
            if let step = field.step, field.min != nil { properties["step"] = step }
            control = ["type": "Slider", "id": field.viewID, "properties": properties]
        case .date:
            properties["title"] = label
            properties["displayedComponents"] = "date"
            if let date = field.defaultValue?.string { properties["selectedDate"] = date }
            return ["type": "DatePicker", "id": field.viewID, "properties": properties]
        }
        // Controls without a title of their own get their label from LabeledContent, which lines it
        // up with the other rows of the Form.
        return ["type": "LabeledContent", "properties": ["title": label], "children": [control]]
    }

    private func buttonElement(_ button: DialogButton) -> [String: Any] {
        var properties: [String: Any] = ["title": button.title, "actionID": button.actionID,
                                         "buttonStyle": button.isDefault ? "borderedProminent" : "bordered"]
        if button.isDefault {
            properties["keyboardShortcut"] = ["key": "return"]
        } else if button.isCancel {
            properties["keyboardShortcut"] = ["key": "escape"]
            properties["role"] = "cancel"
        }
        return ["type": "Button", "properties": properties]
    }

    /// A default value as the text a text field shows.
    static func text(of value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .int(let number): return String(number)
        case .double(let number): return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .bool(let flag): return flag ? "true" : "false"
        default: return ""
        }
    }
}

// MARK: - show

enum ContentKind: String, CaseIterable {
    case markdown, text, image, pdf, file, video, web
}

struct ViewerSpec {
    let title: String
    let kind: ContentKind
    let root: [String: Any]
    let width: Double
    let height: Double

    init(arguments: [String: JSONValue]) throws {
        guard let title = arguments["title"]?.string, !title.isEmpty else {
            throw MCPToolError("'title' is required and must be a non-empty string")
        }
        self.title = title
        let kindName = arguments["kind"]?.string ?? ""
        guard let kind = ContentKind(rawValue: kindName) else {
            let known = ContentKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("'kind' must be one of: \(known)")
        }
        self.kind = kind
        self.width = min(max(arguments["width"]?.double ?? 800, 240), 3000)
        self.height = min(max(arguments["height"]?.double ?? 600, 160), 3000)

        let text = arguments["text"]?.string
        let path = arguments["path"]?.string
        let url = arguments["url"]?.string
        // Local files go through 'path', which checks them; a url is for the network only.
        if let url, !(url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://")) {
            throw MCPToolError("'url' must start with http:// or https://; use 'path' for a local file")
        }
        let fill: [String: Any] = ["maxWidth": "infinity", "maxHeight": "infinity"]

        switch kind {
        case .markdown:
            guard let text else { throw MCPToolError("kind 'markdown' needs 'text'") }
            root = ["type": "ScrollView", "properties": ["frame": fill],
                    "content": ["type": "RichText", "properties": ["markdown": text, "padding": 20]]]
        case .text:
            guard let text else { throw MCPToolError("kind 'text' needs 'text'") }
            root = ["type": "TextEditor", "properties": ["text": text, "readOnly": true, "frame": fill,
                                                         "font": ["size": 12, "design": "monospaced"]]]
        case .image:
            if let path {
                root = ["type": "Image", "properties": ["filePath": try Self.existingFile(path), "resizable": true,
                                                        "contentMode": "fit", "padding": 12, "frame": fill]]
            } else if let url {
                root = ["type": "AsyncImage", "properties": ["url": url, "frame": fill]]
            } else {
                throw MCPToolError("kind 'image' needs 'path' or 'url'")
            }
        case .pdf, .file:
            guard let path else { throw MCPToolError("kind '\(kind.rawValue)' needs 'path'") }
            root = ["type": "QuickLook", "properties": ["filePath": try Self.existingFile(path), "frame": fill]]
        case .video:
            let location: String
            if let path {
                location = URL(fileURLWithPath: try Self.existingFile(path)).absoluteString
            } else if let url {
                location = url
            } else {
                throw MCPToolError("kind 'video' needs 'path' or 'url'")
            }
            root = ["type": "VideoPlayer", "properties": ["url": location, "frame": fill]]
        case .web:
            if let url {
                root = ["type": "WebView", "properties": ["url": url, "frame": fill]]
            } else if let text {
                root = ["type": "WebView", "properties": ["html": text, "frame": fill]]
            } else {
                throw MCPToolError("kind 'web' needs 'url', or 'text' holding HTML")
            }
        }
    }

    /// Paths must be absolute: the server does not share the client's working directory.
    private static func existingFile(_ path: String) throws -> String {
        guard path.hasPrefix("/") else { throw MCPToolError("'path' must be absolute: \(path)") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw MCPToolError("no such file: \(path)")
        }
        return path
    }
}
