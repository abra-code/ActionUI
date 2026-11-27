// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// CannedUI.swift - the ActionUI JSON the canned tools show. The agent passes a few typed
// parameters; the server assembles the ActionUI JSON here, so the agent never writes ActionUI syntax
// for a simple dialog or viewer.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import MCPStdio

// MARK: - Agent Markdown

/// A RichText element for Markdown the agent wrote in a canned tool's message (ask_user, notify):
/// the whole of Markdown (headings, lists, quotes, code blocks, tables) on every platform, where a
/// Text draws only inline styles. Remote images are never fetched: an image address can carry data
/// out, and the user did not open a dialog or a notice to read a page. No baseURL, so relative image
/// paths do not resolve.
func agentMarkdown(_ text: String, size: Double) -> [String: Any] {
    ["type": "RichText",
     "properties": ["markdown": text, "baseFontSize": size, "widthBehavior": "fill", "remoteImages": "never",
                    "frame": ["maxWidth": "infinity", "alignment": "leading"]]]
}

// MARK: - ask_user

enum FieldKind: String, CaseIterable {
    case text, multiline, number, integer, toggle, choice, multichoice, slider, date
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

    /// A dialog button's actionID is this prefix, a token new for each set of buttons, and the
    /// button's index. The token keeps ActionUI JSON from naming a button's actionID itself (an
    /// `onAppearActionID`, or a template row, would otherwise press it without a click).
    static let buttonActionPrefix = "mcp.dialog.button."
    /// A slider reports its moves under this prefix plus its view id, so the host can update its readout.
    static let sliderActionPrefix = "mcp.dialog.slider."
    /// View ids 1... belong to fields; a slider's readout Text is its field's id plus this offset.
    static let firstFieldViewID = 1
    static let readoutViewIDOffset = 10000
    /// A multichoice option's checkbox has view id optionViewIDBase + field id * 1000 + option index.
    static let optionViewIDBase = 100_000
    static let maxMultichoiceOptions = 50
    static let maxFields = 30
    /// Above this estimated height the fields scroll, so a long dialog still fits on the screen.
    private static let maxFormHeight = 480.0

    /// Parses and checks ask_user arguments. Every problem is a message for the agent.
    init(arguments: [String: JSONValue]) throws {
        guard let title = arguments["title"]?.string, !title.isEmpty else {
            throw MCPToolError("'title' is required and must be a non-empty string")
        }
        self.title = oneLine(title, limit: maxAgentTitleLength)
        guard !self.title.isEmpty else { throw MCPToolError("'title' must have something to show, not only spaces") }
        self.message = arguments["message"]?.string
        self.width = min(max(arguments["width"]?.double ?? 460, 320), 1000)

        var fields: [DialogField] = []
        var seenKeys: Set<String> = []
        let rawFields = arguments["fields"]?.array ?? []
        guard rawFields.count <= Self.maxFields else {
            throw MCPToolError("at most \(Self.maxFields) fields per dialog; split the question")
        }
        for (index, raw) in rawFields.enumerated() {
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
            if (kind == .choice || kind == .multichoice) && options.isEmpty {
                throw MCPToolError("fields[\(index)] is a \(kind.rawValue) and needs 'options'")
            }
            if kind == .multichoice {
                guard options.count <= Self.maxMultichoiceOptions else {
                    throw MCPToolError("fields[\(index)] has more than \(Self.maxMultichoiceOptions) options")
                }
                // Each value is one answer; two checkboxes for one value could disagree.
                guard Set(options.map(\.tag)).count == options.count else {
                    throw MCPToolError("fields[\(index)].options values must be unique")
                }
                if let initial = object["default"], initial != .null {
                    guard let list = initial.array, list.allSatisfy({ item in options.contains { $0.tag == item.string } }) else {
                        throw MCPToolError("fields[\(index)].default must be an array of option values")
                    }
                }
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
            if kind == .slider {
                // Without min and max, ActionUI's Slider runs 0...1 and ignores a step.
                if object["step"]?.double != nil && minimum == nil {
                    throw MCPToolError("fields[\(index)] is a slider: 'step' needs 'min' and 'max'")
                }
                let low = minimum ?? 0
                let high = maximum ?? 1
                guard low <= high else {
                    throw MCPToolError("fields[\(index)] is a slider: 'min' must not exceed 'max'")
                }
                if let initial = object["default"]?.double, initial < low || initial > high {
                    throw MCPToolError("fields[\(index)].default \(initial) is outside the slider range \(low)...\(high)")
                }
            }
            fields.append(DialogField(key: key, label: object["label"]?.string ?? key, kind: kind,
                                      defaultValue: object["default"], required: object["required"]?.bool ?? false,
                                      placeholder: object["placeholder"]?.string, options: options,
                                      min: minimum, max: maximum, step: object["step"]?.double,
                                      viewID: Self.firstFieldViewID + index))
        }
        self.fields = fields

        self.buttons = try Self.parseButtons(arguments["buttons"], allowEmpty: false)
    }

    /// Button titles, left to right; ["Cancel", "OK"] when none are given (or, with `allowEmpty`,
    /// only when the key is absent). The last button is the default (Return). A button titled
    /// Cancel is the Escape button and reports action "cancel"; so does closing the window.
    static func parseButtons(_ raw: JSONValue?, allowEmpty: Bool) throws -> [DialogButton] {
        var titles = (raw?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
        if titles.isEmpty && !(allowEmpty && raw?.array != nil) { titles = ["Cancel", "OK"] }
        // Case-insensitive, like the Cancel match below: "Cancel" and "cancel" would be two Escape buttons.
        guard Set(titles.map { $0.lowercased() }).count == titles.count else {
            throw MCPToolError("button titles must be unique")
        }
        let defaultIndex = titles.count - 1
        let prefix = buttonActionPrefix + UUID().uuidString + "."
        return titles.enumerated().map { index, title in
            let isCancel = title.lowercased() == "cancel"
            return DialogButton(title: title, isDefault: index == defaultIndex && !isCancel, isCancel: isCancel,
                                actionID: prefix + String(index))
        }
    }

    func ui(footer: String) -> [String: Any] {
        // The title is the window title; the message is the heading of the content.
        var children: [[String: Any]] = []
        if let message, !message.isEmpty {
            children.append(agentMarkdown(message, size: 14))
        }
        if !fields.isEmpty {
            let form: [String: Any] = ["type": "Form", "children": fields.map(fieldElement)]
            let estimatedHeight = fields.reduce(0) { $0 + Self.estimatedHeight(of: $1) }
            if estimatedHeight > Self.maxFormHeight {
                children.append(["type": "ScrollView", "properties": ["frame": ["height": Self.maxFormHeight]], "content": form])
            } else {
                children.append(form)
            }
        }
        children.append(["type": "Text", "properties": ["text": footer, "font": "caption", "foregroundStyle": "secondary",
                                                       "frame": ["maxWidth": "infinity", "alignment": "leading"]]])
        children.append(Self.buttonRow(buttons))
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
        case .multichoice:
            let checked = Set((field.defaultValue?.array ?? []).compactMap(\.string))
            let boxes: [[String: Any]] = field.options.enumerated().map { index, option in
                ["type": "Toggle", "id": Self.optionViewID(field, index),
                 "properties": ["title": option.title, "isOn": checked.contains(option.tag), "style": "checkbox"]]
            }
            // The field's id on the stack: fieldValues reads every field id, and a missing one logs a warning.
            control = ["type": "VStack", "id": field.viewID, "properties": ["alignment": "leading", "spacing": 4], "children": boxes]
        case .slider:
            properties["value"] = field.defaultValue?.double ?? field.min ?? 0
            if let min = field.min, let max = field.max { properties["range"] = ["min": min, "max": max] }
            if let step = field.step, field.min != nil { properties["step"] = step }
            properties["valueChangeActionID"] = Self.sliderActionPrefix + String(field.viewID)
            properties["frame"] = ["maxWidth": "infinity"]
            let initial = properties["value"] as? Double ?? 0
            let readout: [String: Any] = ["type": "Text", "id": field.viewID + Self.readoutViewIDOffset,
                                          "properties": ["text": Self.readout(initial, for: field),
                                                         "font": ["size": 12, "design": "monospaced"],
                                                         "frame": ["minWidth": 64, "alignment": "trailing"]]]
            control = ["type": "HStack", "properties": ["spacing": 8],
                       "children": [["type": "Slider", "id": field.viewID, "properties": properties], readout]]
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

    /// View id of a multichoice option's checkbox.
    static func optionViewID(_ field: DialogField, _ index: Int) -> Int {
        optionViewIDBase + field.viewID * 1000 + index
    }

    static func buttonRow(_ buttons: [DialogButton]) -> [String: Any] {
        ["type": "HStack", "properties": ["spacing": 8], "children": [["type": "Spacer"]] + buttons.map(buttonElement)]
    }

    private static func buttonElement(_ button: DialogButton) -> [String: Any] {
        var properties: [String: Any] = ["title": button.title, "actionID": button.actionID,
                                         "buttonStyle": button.isDefault ? "borderedProminent" : "bordered"]
        // "modifiers": [] is required: an omitted modifiers key means Command in ActionUI, which
        // would bind Command-Return and Command-Escape instead of the plain keys a dialog needs.
        if button.isDefault {
            properties["keyboardShortcut"] = ["key": "return", "modifiers": [String]()]
        } else if button.isCancel {
            properties["keyboardShortcut"] = ["key": "escape", "modifiers": [String]()]
            properties["role"] = "cancel"
        }
        return ["type": "Button", "properties": properties]
    }

    /// A slider value as its readout shows it: as many decimals as the step has (none for whole
    /// steps); without a step, whole numbers for wide ranges and two decimals for narrow ones.
    static func readout(_ value: Double, for field: DialogField) -> String {
        let decimals: Int
        if let step = field.step, step > 0 {
            var places = 0
            var scaled = step
            while places < 3 && abs(scaled - scaled.rounded()) > 1e-9 {
                scaled *= 10
                places += 1
            }
            decimals = places
        } else {
            decimals = (field.max ?? 1) - (field.min ?? 0) >= 10 ? 0 : 2
        }
        return HostSupport.fixed(value, decimals: decimals)
    }

    /// Rough row heights of the macOS Form, used only to decide when the fields must scroll.
    private static func estimatedHeight(of field: DialogField) -> Double {
        switch field.kind {
        case .multiline: return 130
        case .choice where field.options.count <= 4: return Double(field.options.count) * 22 + 8
        case .multichoice: return Double(field.options.count) * 22 + 8
        default: return 30
        }
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
    case markdown, text, image, pdf, file, video, web, diff, table, chart

    /// The kinds this system can show. Quick Look (pdf) has no renderer on Linux; file shows there
    /// what ActionUI's own views can show (FileViewing).
    static var available: [ContentKind] {
        #if os(Linux) || os(Windows)
        allCases.filter { $0 != .pdf }
        #else
        allCases
        #endif
    }
}

/// What the bar of a `show` window says: when the window was shown, and where its content
/// came from.
struct ShowFooter: Codable, Sendable {
    let shownAt: Date
    /// The local file shown, its links resolved; nil for inline content and for a diff.
    let path: String?
    /// The http(s) address shown, for content from the network.
    let url: String?
    /// What the Save button writes; nil when there is none (content from the network).
    let save: ShowSave?

    /// The source as the bar shows it. A line break in a file name would make the label taller
    /// than the bar and draw it over the content, and a direction override (U+202A-202E,
    /// U+2066-2069) could make "x<RLO>txt.app" read as a text file: these show as "?", as ls
    /// shows control characters.
    static func shownSource(_ source: String) -> String {
        String(String.UnicodeScalarView(source.unicodeScalars.map { scalar in
            if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) { return "?" }
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return "?"
            default: return scalar
            }
        }))
    }
}

struct ViewerSpec {
    let title: String
    let kind: ContentKind
    let root: [String: Any]
    let width: Double
    let height: Double
    /// For `table`: the rows, set through the value API once the window exists (Table takes its
    /// rows as state, not as a property).
    let tableRows: [[String]]?
    /// For `chart`: the warnings of the ActionUI JSON checks, returned with the result.
    let warnings: [String]
    /// For `file`: the view the file is shown with, returned with the result.
    let shownAs: FileView?
    /// Where the content came from, for the bar: a local file, or an http(s) address.
    let sourcePath: String?
    let sourceURL: String?
    let save: ShowSave?

    static let tableViewID = 1
    static let chartViewID = 1
    static let maxTableRows = 50000

    init(arguments: [String: JSONValue]) throws {
        guard let title = arguments["title"]?.string, !title.isEmpty else {
            throw MCPToolError("'title' is required and must be a non-empty string")
        }
        self.title = oneLine(title, limit: maxAgentTitleLength)
        guard !self.title.isEmpty else { throw MCPToolError("'title' must have something to show, not only spaces") }
        let kindName = arguments["kind"]?.string ?? ""
        guard let kind = ContentKind(rawValue: kindName), ContentKind.available.contains(kind) else {
            let known = ContentKind.available.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("'kind' must be one of: \(known)")
        }
        self.kind = kind
        self.width = min(max(arguments["width"]?.double ?? 800, 240), 3000)
        self.height = min(max(arguments["height"]?.double ?? 600, 160), 3000)

        let text = arguments["text"]?.string
        let path = arguments["path"]?.string
        let url = arguments["url"]?.string
        // The kind first, so an agent that passed 'base' to the wrong kind hears that, not a path problem.
        if arguments["base"]?.string != nil, kind != .markdown {
            throw MCPToolError("'base' is for kind 'markdown' only")
        }
        let base = try arguments["base"]?.string.map(Self.existingBase)
        // Local files go through 'path', which checks them; a url is for the network only.
        if let url, !(url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://")) {
            throw MCPToolError("'url' must start with http:// or https://; use 'path' for a local file")
        }
        let fill: [String: Any] = ["maxWidth": "infinity", "maxHeight": "infinity"]

        var parsedRows: [[String]]?
        var checkWarnings: [String] = []
        var fileView: FileView?
        var shownPath: String?
        var shownURL: String?
        switch kind {
        case .markdown:
            guard let text else { throw MCPToolError("kind 'markdown' needs 'text'") }
            var properties: [String: Any] = ["markdown": text, "padding": 20]
            // Relative image paths in the text resolve against the folder the agent names.
            if let base { properties["baseURL"] = base.path }
            root = ["type": "ScrollView", "properties": ["frame": fill], "content": ["type": "RichText", "properties": properties]]
        case .text:
            guard let text else { throw MCPToolError("kind 'text' needs 'text'") }
            root = ["type": "TextEditor", "properties": ["text": text, "readOnly": true, "frame": fill,
                                                         "font": ["size": 12, "design": "monospaced"]]]
        case .image:
            if let path {
                root = ["type": "Image", "properties": ["filePath": try Self.existingFile(path), "resizable": true,
                                                        "contentMode": "fit", "padding": 12, "frame": fill]]
                shownPath = path
            } else if let url {
                root = ["type": "AsyncImage", "properties": ["url": url, "frame": fill]]
                shownURL = url
            } else {
                throw MCPToolError("kind 'image' needs 'path' or 'url'")
            }
        case .pdf:
            guard let path else { throw MCPToolError("kind 'pdf' needs 'path'") }
            root = ["type": "QuickLook", "properties": ["filePath": try Self.existingFile(path), "frame": fill]]
            shownPath = path
        case .file:
            guard let path else { throw MCPToolError("kind 'file' needs 'path'") }
            let viewing = try FileViewing.view(forPath: try Self.existingFile(path), tableViewID: Self.tableViewID,
                                               maxTableRows: Self.maxTableRows)
            root = viewing.root
            parsedRows = viewing.rows
            fileView = viewing.view
            shownPath = path
        case .video:
            let location: String
            if let path {
                location = URL(fileURLWithPath: try Self.existingFile(path)).absoluteString
                shownPath = path
            } else if let url {
                location = url
                shownURL = url
            } else {
                throw MCPToolError("kind 'video' needs 'path' or 'url'")
            }
            root = ["type": "VideoPlayer", "properties": ["url": location, "frame": fill]]
        case .web:
            if let url {
                root = ["type": "WebView", "properties": ["url": url, "frame": fill]]
                shownURL = url
            } else if let text {
                root = ["type": "WebView", "properties": ["html": text, "frame": fill]]
            } else {
                throw MCPToolError("kind 'web' needs 'url', or 'text' holding HTML")
            }
        case .diff:
            // Each side is inline text or a file; the Diff element reads files itself.
            var properties: [String: Any] = ["padding": 12]
            for (side, textKey, pathKey) in [("old", "old_text", "old_path"), ("new", "new_text", "new_path")] {
                if let sideText = arguments[textKey]?.string {
                    properties[side + "Text"] = sideText
                } else if let sidePath = arguments[pathKey]?.string {
                    properties[side + "File"] = try Self.existingFile(sidePath, key: pathKey)
                } else {
                    throw MCPToolError("kind 'diff' needs '\(textKey)' or '\(pathKey)'")
                }
            }
            root = ["type": "ScrollView", "properties": ["frame": fill],
                    "content": ["type": "Diff", "properties": properties]]
        case .table:
            let rawColumns = arguments["columns"]?.array ?? []
            let columns = rawColumns.compactMap(\.string)
            guard !columns.isEmpty, columns.count == rawColumns.count else {
                throw MCPToolError("kind 'table' needs 'columns', a non-empty array of strings")
            }
            var rawRows: [JSONValue] = []
            if let given = arguments["rows"], given != .null {
                guard let list = given.array else { throw MCPToolError("'rows' must be an array of rows") }
                rawRows = list
            }
            guard rawRows.count <= Self.maxTableRows else {
                throw MCPToolError("at most \(Self.maxTableRows) table rows")
            }
            var rows: [[String]] = []
            rows.reserveCapacity(rawRows.count)
            for (index, rawRow) in rawRows.enumerated() {
                guard let cells = rawRow.array, cells.count <= columns.count else {
                    throw MCPToolError("rows[\(index)] must be an array of at most \(columns.count) cells")
                }
                // Short rows are padded, so every row has one cell per column.
                let texts = cells.map(DialogSpec.text(of:))
                rows.append(texts + Array(repeating: "", count: columns.count - texts.count))
            }
            parsedRows = rows
            root = ["type": "Table", "id": Self.tableViewID, "properties": ["columns": columns, "frame": fill]]
        case .chart:
            guard let chart = arguments["chart"], case .object = chart else {
                throw MCPToolError("kind 'chart' needs 'chart', a chart description object such as {\"columns\": [...], \"data\": [...], \"content\": [...]}")
            }
            if arguments["columns"] != nil || arguments["rows"] != nil {
                throw MCPToolError("kind 'chart' takes its columns and data inside 'chart'")
            }
            // The description is the agent's, so the window's ActionUI JSON gets the checks of show_ui,
            // the verifier among them, and its warnings go back with the result.
            let ui: AgentUI
            do {
                ui = try AgentUI(arguments: ["ui": [
                    "type": "Chart", "id": .int(Self.chartViewID),
                    "properties": ["chart": chart, "padding": 16, "frame": ["maxWidth": "infinity", "maxHeight": "infinity"]],
                ]])
            } catch let error as MCPToolError {
                // The agent passed a description, not a whole window's ActionUI JSON: name it and its paths so.
                throw MCPToolError(error.message
                    .replacing("the ActionUI JSON has errors:", with: "the chart description has errors:")
                    .replacing("root: properties.chart", with: "chart")
                    .replacing("root.properties.chart", with: "chart"))
            }
            root = ui.foundation
            checkWarnings = ui.warnings
        }
        tableRows = parsedRows
        warnings = checkWarnings
        shownAs = fileView
        sourcePath = shownPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        sourceURL = shownURL
        save = ShowSave.forViewer(kind: kind, title: self.title, arguments: arguments, sourcePath: sourcePath)
    }

    /// The bar of a window showing this, opened now.
    func footer() -> ShowFooter {
        ShowFooter(shownAt: Date(), path: sourcePath, url: sourceURL, save: save)
    }

    /// The folder that relative paths in `text` resolve against: `base`, an existing folder, or the
    /// folder of an existing file in it. Absolute, as every path the server takes.
    private static func existingBase(_ path: String) throws -> URL {
        guard HostSupport.isAbsolutePath(path) else { throw MCPToolError("'base' must be absolute: \(path)") }
        guard let isFolder = HostSupport.isFolder(atPath: path) else { throw MCPToolError("no such folder or file: \(path)") }
        let url = URL(fileURLWithPath: path, isDirectory: isFolder)
        return isFolder ? url : url.deletingLastPathComponent()
    }

    /// Paths must be absolute: the server does not share the client's working directory.
    private static func existingFile(_ path: String, key: String = "path") throws -> String {
        guard HostSupport.isAbsolutePath(path) else { throw MCPToolError("'\(key)' must be absolute: \(path)") }
        guard HostSupport.isFolder(atPath: path) == false else { throw MCPToolError("no such file: \(path)") }
        return path
    }
}
