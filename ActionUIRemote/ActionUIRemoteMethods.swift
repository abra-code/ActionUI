// ActionUIRemote/ActionUIRemoteMethods.swift
//
// The built-in `actionui.*` method table, one handler per row of PROTOCOL.md section 6.4, each a
// thin adapter from named JSON params to ActionUIModel.shared. Everything here runs on the main
// actor (MethodRegistry.execute). Values returned to the codec are JSON-ready: engine values
// that have no JSON form (Date, Color, coordinates) come back as null, and getValueString is
// the supported path for those, exactly as with the C adapter.

#if os(macOS)

import Foundation
import ActionUI

enum ActionUIRemoteMethods {

    @MainActor
    static func install(into registry: MethodRegistry, server: ActionUIRemoteServer) {
        let model = ActionUIModel.shared
        var table: [String: ActionUIRemoteServer.Handler] = [:]

        // MARK: Discovery

        table["actionui.hello"] = { [weak server, unowned registry] _ in
            var hello: [String: Any] = [
                "protocolVersion": ActionUIRemoteServer.protocolVersion,
                "methods": registry.methodNames,
                "windows": model.windowUUIDs,
            ]
            if let server {
                hello["host"] = ["name": server.host.name, "version": server.host.version]
            }
            return hello
        }
        table["actionui.listWindows"] = { _ in
            return model.windowUUIDs
        }
        table["actionui.getElementInfo"] = { raw in
            let p = Params(raw)
            let window = try p.window()
            var info: [String: String] = [:]
            for (id, type) in model.getElementInfo(windowUUID: window) {
                info[String(id)] = type
            }
            return info
        }

        // MARK: Values

        table["actionui.getValue"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return jsonReady(model.getElementValue(windowUUID: window, viewID: viewID, viewPartID: try p.viewPartID()))
        }
        table["actionui.setValue"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            let value = try p.required("value")
            model.setElementValue(windowUUID: window, viewID: viewID, viewPartID: try p.viewPartID(), value: value)
            return true
        }
        table["actionui.getValueString"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return model.getElementValueAsString(windowUUID: window, viewID: viewID, viewPartID: try p.viewPartID(),
                                                 contentType: try p.optionalString("contentType"))
        }
        table["actionui.setValueString"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.setElementValueFromString(windowUUID: window, viewID: viewID, viewPartID: try p.viewPartID(),
                                            value: try p.string("value"), contentType: try p.optionalString("contentType"))
            return true
        }

        // MARK: Properties

        table["actionui.getProperty"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return jsonReady(model.getElementProperty(windowUUID: window, viewID: viewID, propertyName: try p.string("name")))
        }
        table["actionui.setProperty"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.setElementProperty(windowUUID: window, viewID: viewID, propertyName: try p.string("name"),
                                     value: try p.required("value"))
            return true
        }

        // MARK: State

        table["actionui.getState"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return jsonReady(model.getElementState(windowUUID: window, viewID: viewID, key: try p.string("key")))
        }
        table["actionui.getStateString"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return model.getElementStateAsString(windowUUID: window, viewID: viewID, key: try p.string("key"))
        }
        table["actionui.setState"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            let key = try p.string("key")
            // JSON-decoded scalars are NSNumber and NSString; the engine compares state types
            // exactly against what Swift code stored (Bool, Int, Double, String), so coerce toward
            // the existing value's type first, or to the Swift-native type for a new key.
            let existing = model.getElementState(windowUUID: window, viewID: viewID, key: key)
            let value = coerceState(try p.required("value"), toTypeOf: existing)
            // The engine rejects a remaining type change by logging and returning; mirror its
            // check so the client learns about it (1003) instead of reading the old value later.
            if let existing, type(of: existing) != type(of: value) {
                throw ActionUIRemoteError(
                    code: ActionUIRemoteError.engineFailure,
                    message: "Type mismatch for state key '\(key)' on viewID: \(viewID); expected \(type(of: existing)), got \(type(of: value))")
            }
            model.setElementState(windowUUID: window, viewID: viewID, key: key, value: value)
            return true
        }
        table["actionui.setStateString"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.setElementStateFromString(windowUUID: window, viewID: viewID, key: try p.string("key"), value: try p.string("value"))
            return true
        }

        // MARK: Rows and selection

        table["actionui.getColumnCount"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return model.getElementColumnCount(windowUUID: window, viewID: viewID)
        }
        table["actionui.getRows"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return model.getElementRows(windowUUID: window, viewID: viewID)
        }
        table["actionui.setRows"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.setElementRows(windowUUID: window, viewID: viewID, rows: try p.rows("rows"))
            return true
        }
        table["actionui.appendRows"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.appendElementRows(windowUUID: window, viewID: viewID, rows: try p.rows("rows"))
            return true
        }
        table["actionui.clearRows"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.clearElementRows(windowUUID: window, viewID: viewID)
            return true
        }
        table["actionui.selectRow"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return model.selectElementRow(windowUUID: window, viewID: viewID, index: try p.int("index"))
        }
        table["actionui.selectRowWithContent"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            return model.selectElementRow(windowUUID: window, viewID: viewID, matching: try p.string("text"),
                                          column: try p.optionalInt("column")) ?? -1
        }
        table["actionui.clearSelection"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            model.clearElementSelection(windowUUID: window, viewID: viewID)
            return true
        }

        // MARK: Structural mutation

        table["actionui.insertElement"] = { raw in
            let p = Params(raw)
            let window = try p.window()
            let parentID = try p.int("parentID")
            let element = try p.object("element")
            let container = try p.optionalString("container")
            let position = try p.insertPosition()
            return try engine {
                try model.insertElement(windowUUID: window, parentID: parentID, dict: element, container: container, position: position)
            }
        }
        table["actionui.insertRow"] = { raw in
            let p = Params(raw)
            let window = try p.window()
            let parentID = try p.int("parentID")
            let cells = try p.objects("cells")
            let container = try p.optionalString("container")
            let position = try p.insertPosition()
            return try engine {
                try model.insertRow(windowUUID: window, parentID: parentID, cells: cells, container: container, position: position)
            }
        }
        table["actionui.removeElement"] = { raw in
            let p = Params(raw)
            let (window, viewID) = try p.windowAndView()
            try engine {
                try model.removeElement(windowUUID: window, viewID: viewID)
            }
            return true
        }

        // MARK: Presentation

        table["actionui.presentModal"] = { [unowned registry] raw in
            let p = Params(raw)
            let window = try p.window()
            let style: ModalStyle
            do {
                style = try ActionUIJSON.modalStyle(from: try p.optionalString("style"))
            } catch let error as ActionUIJSONError {
                throw ActionUIRemoteError.invalidParams(error.message)
            }
            let onDismiss = try p.optionalString("onDismissActionID")
            let (data, format) = try modalSource(p, resolver: registry.modalResolver)
            try engine {
                try model.presentModal(windowUUID: window, data: data, format: format, style: style, onDismissActionID: onDismiss)
            }
            return true
        }
        table["actionui.dismissModal"] = { raw in
            let p = Params(raw)
            model.dismissModal(windowUUID: try p.window())
            return true
        }
        table["actionui.presentAlert"] = { raw in
            let p = Params(raw)
            let window = try p.window()
            let title = try p.string("title")
            let message = try p.optionalString("message")
            if let buttons = try p.dialogButtons("buttons") {
                model.presentAlert(windowUUID: window, title: title, message: message, buttons: buttons)
            } else {
                model.presentAlert(windowUUID: window, title: title, message: message)
            }
            return true
        }
        table["actionui.presentConfirmationDialog"] = { raw in
            let p = Params(raw)
            let window = try p.window()
            guard let buttons = try p.dialogButtons("buttons") else {
                throw ActionUIRemoteError.invalidParams("\"buttons\" is required: a non-empty array of {title, role?, actionID?}")
            }
            model.presentConfirmationDialog(windowUUID: window, title: try p.string("title"),
                                            message: try p.optionalString("message"), buttons: buttons)
            return true
        }
        table["actionui.dismissDialog"] = { raw in
            let p = Params(raw)
            model.dismissDialog(windowUUID: try p.window())
            return true
        }
        table["actionui.presentToast"] = { raw in
            let p = Params(raw)
            let window = try p.window()
            model.presentToast(windowUUID: window, message: try p.string("message"),
                               duration: try p.optionalDouble("duration") ?? 4.0,
                               actionTitle: try p.optionalString("actionTitle"), actionID: try p.optionalString("actionID"))
            return true
        }
        table["actionui.dismissToast"] = { raw in
            let p = Params(raw)
            model.dismissToast(windowUUID: try p.window())
            return true
        }
        table["actionui.contentSizeLimits"] = { raw in
            let p = Params(raw)
            guard let limits = model.contentSizeLimits(windowUUID: try p.window()) else { return nil }
            return [
                "minWidth": limits.minSize.width, "minHeight": limits.minSize.height,
                "maxWidth": limits.maxSize.width, "maxHeight": limits.maxSize.height,
            ]
        }

        registry.handlers.merge(table) { _, builtin in builtin }
    }

    // MARK: - Helpers

    /// Run an engine call that throws and report its failure as `engineFailure` (1003).
    @MainActor
    private static func engine<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ActionUIRemoteError {
            throw error
        } catch {
            throw ActionUIRemoteError(code: ActionUIRemoteError.engineFailure, message: "\(error)")
        }
    }

    /// A JSON-decoded state value converted toward the type of the state already stored, so a
    /// stored Double accepts a whole JSON number and a stored Bool accepts a JSON bool. With no
    /// existing value the Swift-native normalization applies. Anything that does not fit is
    /// returned unchanged and the caller's type check reports it.
    static func coerceState(_ value: Any, toTypeOf existing: Any?) -> Any {
        guard let existing else { return ActionUIJSON.normalized(value) }
        let isBool = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        switch existing {
        case is Bool:
            if let n = value as? NSNumber, isBool { return n.boolValue }
        case is Int:
            if let n = value as? NSNumber, !isBool, let i = Int(exactly: n) { return i }
        case is Double:
            if let n = value as? NSNumber, !isBool { return n.doubleValue }
        case is Float:
            if let n = value as? NSNumber, !isBool { return n.floatValue }
        case is String:
            if let s = value as? String { return s }
        default:
            break
        }
        return ActionUIJSON.normalized(value)
    }

    /// An engine value as the codec can encode it, or nil (null on the wire) when it has no JSON
    /// form. `isValidJSONObject` needs a container, hence the wrapping.
    static func jsonReady(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        if JSONSerialization.isValidJSONObject(["v": value]) {
            return value
        }
        return nil
    }

    /// Where the modal's description comes from: an inline element object, a JSON/plist string,
    /// or a resource name or path resolved by the host.
    @MainActor
    private static func modalSource(_ p: Params, resolver: ActionUIRemoteServer.ModalResourceResolver?) throws -> (Data, String) {
        if let element = p.raw["element"], !(element is NSNull) {
            guard let object = element as? [String: Any], JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
                throw ActionUIRemoteError.invalidParams("\"element\" must be a JSON object describing the modal's root element")
            }
            return (data, "json")
        }
        if let json = try p.optionalString("json") {
            return (Data(json.utf8), try p.optionalString("format") ?? "json")
        }
        if let path = try p.optionalString("path") {
            let url: URL?
            if let resolver {
                url = resolver(path)
            } else if path.hasPrefix("/") {
                url = URL(fileURLWithPath: path)
            } else {
                throw ActionUIRemoteError.invalidParams("\"path\" must be absolute: this host does not resolve resource names")
            }
            guard let url else {
                throw ActionUIRemoteError(code: ActionUIRemoteError.engineFailure, message: "Modal resource not found: \(path)")
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ActionUIRemoteError(code: ActionUIRemoteError.engineFailure, message: "Cannot read modal resource \(url.path): \(error.localizedDescription)")
            }
            // An explicit format wins; otherwise the extension decides.
            let format = try p.optionalString("format") ?? (url.pathExtension.lowercased() == "plist" ? "plist" : "json")
            return (data, format)
        }
        throw ActionUIRemoteError.invalidParams("presentModal needs one of \"element\" (object), \"json\" (string), or \"path\" (string)")
    }
}

// MARK: - Params

/// Typed access to a request's named params with `-32602` errors that name the offending key.
/// Numbers decoded from JSON are NSNumber; a JSON bool is an NSNumber too (CFBoolean) and is
/// never accepted where an integer or a double is expected.
struct Params {
    let raw: [String: Any]

    init(_ raw: [String: Any]) {
        self.raw = raw
    }

    // MARK: Windows and views

    @MainActor
    func window() throws -> String {
        let uuid = try string("window")
        guard ActionUIModel.shared.hasWindow(uuid) else {
            throw ActionUIRemoteError(code: ActionUIRemoteError.unknownWindow, message: "Unknown window: \(uuid)")
        }
        return uuid
    }

    @MainActor
    func windowAndView() throws -> (String, Int) {
        let uuid = try window()
        let viewID = try int("viewID")
        guard ActionUIModel.shared.hasElement(windowUUID: uuid, viewID: viewID) else {
            throw ActionUIRemoteError(code: ActionUIRemoteError.unknownView, message: "Unknown view \(viewID) in window \(uuid)")
        }
        return (uuid, viewID)
    }

    func viewPartID() throws -> Int {
        return try optionalInt("viewPartID") ?? 0
    }

    // MARK: Scalars

    func required(_ key: String) throws -> Any {
        guard let value = raw[key], !(value is NSNull) else {
            throw ActionUIRemoteError.invalidParams("Missing required param \"\(key)\"")
        }
        return value
    }

    func string(_ key: String) throws -> String {
        guard let value = try optionalString(key) else {
            throw ActionUIRemoteError.invalidParams("Missing required string param \"\(key)\"")
        }
        return value
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = raw[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else {
            throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be a string")
        }
        return text
    }

    func int(_ key: String) throws -> Int {
        guard let value = try optionalInt(key) else {
            throw ActionUIRemoteError.invalidParams("Missing required integer param \"\(key)\"")
        }
        return value
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = raw[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), let exact = Int(exactly: number) {
            return exact
        }
        throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be an integer")
    }

    func optionalDouble(_ key: String) throws -> Double? {
        guard let value = raw[key], !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.doubleValue
        }
        throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be a number")
    }

    // MARK: Structures

    func object(_ key: String) throws -> [String: Any] {
        guard let value = raw[key], let object = value as? [String: Any] else {
            throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be an object")
        }
        return object
    }

    func objects(_ key: String) throws -> [[String: Any]] {
        guard let value = raw[key], let array = value as? [Any] else {
            throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be an array of objects")
        }
        return try array.map { item in
            guard let object = item as? [String: Any] else {
                throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be an array of objects")
            }
            return object
        }
    }

    /// `[[String]]`: an array of rows, each an array of strings.
    func rows(_ key: String) throws -> [[String]] {
        guard let value = raw[key], let array = value as? [Any] else {
            throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be an array of rows (arrays of strings)")
        }
        return try array.map { row in
            guard let cells = row as? [Any] else {
                throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be an array of rows (arrays of strings)")
            }
            return try cells.map { cell in
                guard let text = cell as? String else {
                    throw ActionUIRemoteError.invalidParams("Param \"\(key)\": every cell must be a string")
                }
                return text
            }
        }
    }

    func insertPosition() throws -> InsertPosition {
        do {
            return try ActionUIJSON.insertPosition(from: raw["position"])
        } catch let error as ActionUIJSONError {
            throw ActionUIRemoteError.invalidParams(error.message)
        }
    }

    /// Dialog buttons, or nil when the param is absent. A present but unusable value is an error.
    func dialogButtons(_ key: String) throws -> [DialogButton]? {
        guard let value = raw[key], !(value is NSNull) else { return nil }
        guard let buttons = ActionUIJSON.dialogButtons(from: value), !buttons.isEmpty else {
            throw ActionUIRemoteError.invalidParams("Param \"\(key)\" must be a non-empty array of {title, role?, actionID?}")
        }
        return buttons
    }
}

#endif
