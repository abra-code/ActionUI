// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AgentDocuments.swift - ActionUI JSON written by the agent (show_ui,
// validate_ui). A document arrives as a JSON object nested in the tool arguments, or as an
// absolute path to a .json file, never as a string. Before anything loads it gets structural
// checks for the mistakes ActionUI's loader would silently ignore, and the safety rules of the
// design: no SecureField (every answer reaches the model), no LoadableView (the document it loads
// would skip these checks), no WindowGroup (its commands would stay in the application's menu after
// its window closes), no popover and no secondaryAction toolbar items (each can open over the
// window's "Requested by" line), no WebView user scripts.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
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
    static let allowSecureFields = ProcessInfo.processInfo.environment["ACTIONUI_MCP_ALLOW_SECURE_FIELDS"] == "1"
    /// A LoadableView loads another document when it is shown, past every check here, through any
    /// of its sources (`url`, `filePath`, `name`) or a new value.
    static let loadableViewRefusal = "LoadableView is not allowed; the ActionUI JSON it loads would skip these checks, so put its content inline"
    /// On Linux a toolbar's secondaryAction items show in the header bar's "More" popover, which,
    /// like a document's popover, opens over the "Requested by" line when it does not fit below
    /// the bar (measured: a window moved low on the screen).
    static let secondaryActionRefusal = "placement \"secondaryAction\" is not allowed; its items open in a popover that can cover the window's \"Requested by\" line, so use another placement"
    static func isSecondaryActionItem(type: String, placement: JSONValue?) -> Bool {
        ["ToolbarItem", "ToolbarItemGroup"].contains(type) && placement?.string == "secondaryAction"
    }

    /// The rules for one property an agent sets on an element of an open window (update_window
    /// `properties`): the document's safety rules, then the ActionUIVerifier on a synthetic
    /// element `{"type", "id", "properties": {name: value}}`. Returns the reason the property is
    /// refused, or nil, the verifier's warnings, and the value to set: a Chart's description
    /// resolved and checked as a document is (Chart resolves platform suffixes inside it, and its
    /// annotations hold elements), any other value as given.
    static func checkProperty(type: String, id: Int, name: String, value: JSONValue)
        -> (refusal: String?, warnings: [String], value: JSONValue) {
        let here = "id \(id) (\(type)) \(name)"
        if value == .null {
            return ("\(here): a property needs a value", [], value)
        }
        if type == "SecureField" && !allowSecureFields {
            return ("\(here): SecureField is not allowed; whatever the user types is sent to the AI agent", [], value)
        }
        if type == "LoadableView" {
            return ("\(here): \(loadableViewRefusal)", [], value)
        }
        // setElementProperty stores the name as given and does not resolve "<name>:<platform>"
        // overrides, so a suffixed name would do nothing now and is a way around the rules below
        // if that ever changes.
        if name.contains(":") {
            return ("\(here): platform suffixes are not resolved here; set the plain property name", [], value)
        }
        if name == "userScripts" {
            return ("\(here): userScripts is refused; user scripts from an agent are not injected", [], value)
        }
        if containerKeys.contains(name) || childArrayKeys.contains(name) || ["id", "type"].contains(name) {
            return ("\(here): \"\(name)\" is not a property; child elements and ids are set by the window's ActionUI JSON", [], value)
        }
        if name == "placement", isSecondaryActionItem(type: type, placement: value) {
            return ("\(here): \(secondaryActionRefusal)", [], value)
        }
        var checked = value
        var safetyWarnings: [String] = []
        if type == "Chart", name == "chart" {
            var errors: [String] = []
            do {
                checked = checkAnnotations(in: try resolvingPlatformSuffixes(value), at: "id \(id) (Chart) chart",
                                           errors: &errors, warnings: &safetyWarnings)
            } catch {
                errors.append("\(here): \((error as? MCPToolError)?.message ?? "\(error)")")
            }
            if !errors.isEmpty {
                return (errors.joined(separator: "; "), safetyWarnings, value)
            }
        }
        guard let validator = Verifier.validator else {
            return (nil, safetyWarnings + [Verifier.unavailableWarning], checked)
        }
        let node: [String: Any] = ["type": type, "id": id, "properties": [name: value.any]]
        var errors: [String] = []
        var warnings = safetyWarnings
        for issue in validator.validate(jsonObject: node, rootPath: "id \(id)") {
            switch issue.severity {
            case .error: errors.append("\(issue.path): \(issue.message)")
            case .warning: warnings.append("\(issue.path): \(issue.message)")
            default: break
            }
        }
        return (errors.isEmpty ? nil : errors.joined(separator: "; "), warnings, checked)
    }

    /// `value` with every "<key>:<platform>" override resolved as ActionUI resolves a document's.
    /// One pass strips only the last suffix ("type:macos:macos" becomes "type:macos"), and the
    /// loader resolves what it is given once more, so resolve until no suffix is left: otherwise
    /// a suffix could hide an element from the checks.
    static func resolvingPlatformSuffixes(_ value: JSONValue) throws -> JSONValue {
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet)
        var resolved = JSONValue(any: filter.filter(value.any))
        var passes = 1
        while true {
            let next = JSONValue(any: filter.filter(resolved.any))
            if next == resolved { break }
            passes += 1
            guard passes <= 8 else { throw MCPToolError("platform suffixes are nested too deeply") }
            resolved = next
        }
        return resolved
    }

    /// Reads `document` (object) or `path` (absolute .json file) from the arguments and checks it.
    /// Throws MCPToolError listing every structural error found.
    init(arguments: [String: JSONValue]) throws {
        let value: JSONValue
        if let document = arguments["ui"], document != .null {
            guard case .object = document else {
                throw MCPToolError("'ui' must be an ActionUI element object such as {\"type\": \"VStack\", ...}, not a string")
            }
            guard document.serialized().utf8.count <= Self.maxBytes else {
                throw MCPToolError("the ActionUI JSON is larger than \(Self.maxBytes / 1024 / 1024) MB")
            }
            value = document
        } else if let path = arguments["path"]?.string {
            value = try Self.load(path: path)
        } else {
            throw MCPToolError("give the ActionUI JSON as 'ui' (an object) or 'path' (an absolute .json path)")
        }

        var errors: [String] = []
        var warnings: [String] = []
        var ids: Set<Int> = []
        // ActionUI resolves "<key>:<platform>" overrides when it loads a document, so the safety
        // rules run on, and the window loads, the resolved document: otherwise "type:macos":
        // "SecureField", "children:macos" or "userScripts:macos" would pass the checks unseen.
        let resolved = try Self.resolvingPlatformSuffixes(value)
        let checked = Self.check(resolved, at: "root", errors: &errors, warnings: &warnings, ids: &ids)
        // Then the ActionUIVerifier checks the document as written (its platform-suffix rules
        // need the suffixes): element types, property names, value types, enums, required
        // properties, platform rules. Its errors refuse the document; its warnings go back with
        // the result.
        if errors.isEmpty {
            if let validator = Verifier.validator {
                for issue in validator.validate(jsonObject: value.any, rootPath: "root") {
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
            throw MCPToolError("the ActionUI JSON has errors:\n" + shown + more)
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
            return try HostSupport.parseJSON(try Data(contentsOf: url))
        } catch {
            throw MCPToolError("\(path) is not valid JSON: \(error.displayText)")
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
                warnings.append("\(here): userScripts removed; user scripts from an agent are not injected")
            }
        } else if object["properties"] != nil {
            errors.append("\(here): \"properties\" must be an object")
        }
        if type == "SecureField" && !allowSecureFields {
            errors.append("\(here): SecureField is not allowed; whatever the user types is sent to the AI agent")
        }
        if type == "LoadableView" {
            errors.append("\(here): \(loadableViewRefusal)")
        }
        if type == "WindowGroup" {
            errors.append("\(here): WindowGroup is not allowed; it is an application's scene, and its commands would stay in the menu after its window closes, so give its content as the root element")
        }
        // A popover is a surface of its own, placed by the system: on macOS and on Linux, one of
        // any size, from an element anywhere, can open over the title bar's "Requested by" line
        // (both flip a popover that does not fit), and show a line of its own there.
        if object["popover"] != nil {
            errors.append("\(here): \"popover\" is not allowed; it can open over the window's \"Requested by\" line, so show its content in the window or in a sheet")
        }
        if isSecondaryActionItem(type: type, placement: object["properties"]?.object?["placement"]) {
            errors.append("\(here): \(secondaryActionRefusal)")
        }
        // A chart description holds elements too: its annotations' views.
        if type == "Chart", var properties = object["properties"]?.object, let chart = properties["chart"] {
            properties["chart"] = checkAnnotations(in: chart, at: "\(location).properties.chart", errors: &errors, warnings: &warnings)
            object["properties"] = .object(properties)
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

    /// A chart description's annotation elements (a mark's or Plot's "annotation" "content"), in
    /// its "content" entries at any depth (ForEach and Plot entries hold more), checked as
    /// document elements are. Their ids are their own, as the verifier counts them: an annotation
    /// is built for each row and never registered.
    private static func checkAnnotations(in description: JSONValue, at location: String, errors: inout [String],
                                         warnings: inout [String]) -> JSONValue {
        guard var object = description.object, case .array(let entries) = object["content"] else { return description }
        object["content"] = .array(entries.enumerated().map { index, entry in
            guard var entryObject = entry.object else { return entry }
            let here = "\(location).content[\(index)]"
            if var annotation = entryObject["annotation"]?.object, let content = annotation["content"], content.object != nil {
                var ids: Set<Int> = []
                annotation["content"] = check(content, at: "\(here).annotation.content", errors: &errors, warnings: &warnings, ids: &ids)
                entryObject["annotation"] = .object(annotation)
            }
            return checkAnnotations(in: .object(entryObject), at: here, errors: &errors, warnings: &warnings)
        })
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

    /// Action properties that fire with no click: when a view appears or disappears, loads, a web
    /// page navigates on its own, the pointer passes, a drag passes over, a URL arrives.
    static let automaticActionKeys: Set<String> = ["onAppearActionID", "onDisappearActionID", "viewDidLoadActionID",
                                                   "navigationActionID", "onHoverActionID", "onDropTargetedActionID",
                                                   "openURLActionID"]
    /// The same, for one element type: a WebView's valueChangeActionID (page script can change the
    /// address), a Map's actionID (it fires on every camera change, the first as the map appears).
    static let automaticActionKeysByType: [String: Set<String>] = ["WebView": ["valueChangeActionID"],
                                                                   "Map": ["actionID"]]

    /// Refuses a document in which a close action can fire with no click, so an "accept" result
    /// means a person did something: a close action bound to an automatic action property (or to a
    /// WebView's valueChangeActionID or a Map's actionID), or, with close actions given, an
    /// automatic action property holding a template column reference ("$1"), which a row could
    /// fill with a close action.
    func checkCloseActions(in document: JSONValue) throws {
        guard !closeActions.isEmpty else { return }
        var problems: [String] = []
        func visit(_ value: JSONValue, at location: String) {
            switch value {
            case .object(let object):
                if let properties = object["properties"]?.object {
                    let typeKeys = object["type"]?.string.flatMap { Self.automaticActionKeysByType[$0] } ?? []
                    for (key, property) in properties.sorted(by: { $0.key < $1.key }) {
                        guard Self.automaticActionKeys.contains(key) || typeKeys.contains(key),
                              let actionID = property.string else { continue }
                        if closeActions.contains(actionID) {
                            problems.append("\(location).properties.\(key): close action \"\(actionID)\" would end the dialog with no click")
                        } else if actionID.contains("$") {
                            problems.append("\(location).properties.\(key): a column reference in an action that fires with no click could name a close action")
                        }
                    }
                }
                for (key, child) in object.sorted(by: { $0.key < $1.key }) where key != "properties" {
                    visit(child, at: "\(location).\(key)")
                }
                // A chart description inside properties holds annotation elements.
                if let chart = object["properties"]?.object?["chart"] {
                    visit(chart, at: "\(location).properties.chart")
                }
            case .array(let items):
                for (index, item) in items.enumerated() { visit(item, at: "\(location)[\(index)]") }
            default:
                break
            }
        }
        visit(document, at: "root")
        if !problems.isEmpty {
            throw MCPToolError("the dialog's close actions must come from a click:\n" + problems.joined(separator: "\n"))
        }
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
