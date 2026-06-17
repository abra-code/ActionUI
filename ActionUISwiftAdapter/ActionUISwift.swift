//
//  ActionUISwift.swift
//  ActionUISwiftAdapter
//

import ActionUI
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Public entry point for the ActionUI Swift adapter, providing a simplified, static API to interact with the core ActionUI library.
/// This struct wraps ActionUIModel to expose methods for setting and getting element values, registering action handlers, and configuring logging.
/// Design decision: Uses static functions to avoid state management, as no adapter-specific state is needed currently.
/// Renamed to SwiftActionUI to avoid naming conflicts with the ActionUISwift module and prevent module interface generation issues.
/// Future extensions may add instance-based state if multiple adapters or configurations are required.
@MainActor
public struct ActionUISwift {
    private static let model = ActionUI.ActionUIModel.shared
    
    /// Sets a custom logger for ActionUI to handle debugging and error reporting.
    /// - Parameter logger: A client-provided logger conforming to ActionUILogger.
    /// Design decision: Delegates to ActionUIModel.setLogger to maintain a single source of truth for logging configuration.
    public static func setLogger(_ logger: any ActionUI.ActionUILogger) {
        model.logger = logger
    }
    
    /// Sets the value of a view element identified by viewID in the specified window.
    /// Supports various value types (e.g., String, Bool, Double, Date) as defined by the view's valueType in ActionUIRegistry.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    ///   - value: The value to set, matching the view's expected type.
    public static func setElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0, value: Any) {
        model.setElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: value)
    }
    
    /// Sets the value of a view element from a string representation, parsing it to the view's expected type.
    /// Supports ISO 8601 for Date, JSON for CLLocationCoordinate2D, and other type conversions per ActionUIModel.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: String representation of the value.
    ///   - contentType: Optional hint for parsing rich-text content ("plain", "markdown", "html", "rtf", "json"). Pass nil for default behavior.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    public static func setElementValueFromString(windowUUID: String, viewID: Int, viewPartID: Int = 0, value: String, contentType: String? = nil) {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: value, contentType: contentType)
    }

    /// Gets the value of a view element identified by viewID in the specified window.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: The value of the view element, or nil if not found or invalid.
    public static func getElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> Any? {
        return model.getElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
    }
    
    /// Gets the string representation of a view element's value.
    /// Uses type-specific formatting (e.g., ISO 8601 for Date, JSON for CLLocationCoordinate2D).
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - contentType: Optional hint for serializing rich-text content ("plain", "json"). Pass nil for default behavior.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: String representation of the value, or nil if not found or invalid.
    public static func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0, contentType: String? = nil) -> String? {
        return model.getElementValueAsString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, contentType: contentType)
    }

    /// Returns the current value for a single state key of a view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key (e.g., "isLoading", "canGoBack").
    /// - Returns: The state value, or nil if the view or key is not found.
    public static func getElementState(windowUUID: String, viewID: Int, key: String) -> Any? {
        return model.getElementState(windowUUID: windowUUID, viewID: viewID, key: key)
    }

    /// Returns the string representation of a single state value.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    /// - Returns: String representation, or nil if the view or key is not found.
    public static func getElementStateAsString(windowUUID: String, viewID: Int, key: String) -> String? {
        return model.getElementStateAsString(windowUUID: windowUUID, viewID: viewID, key: key)
    }

    /// Sets a single state key to a new value.
    /// Rejects the update (with an error log) if the new value's type differs from the existing value's type.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    ///   - value: The new value. Must match the type of the existing value if the key already exists.
    public static func setElementState(windowUUID: String, viewID: Int, key: String, value: Any) {
        model.setElementState(windowUUID: windowUUID, viewID: viewID, key: key, value: value)
    }

    /// Sets a single state key by parsing a string into the type of the existing value.
    /// If the key does not yet exist the string is stored as-is.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    ///   - value: String representation of the new value.
    public static func setElementStateFromString(windowUUID: String, viewID: Int, key: String, value: String) {
        model.setElementStateFromString(windowUUID: windowUUID, viewID: viewID, key: key, value: value)
    }

    /// Returns the number of data columns for a table/list view element.
    /// Reports the maximum column count across all content rows, so hidden columns beyond
    /// the visible ones defined in the JSON layout are included.
    /// Returns 0 for non-table elements or if the view is not found.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    /// - Returns: Number of data columns, or 0 if the view is not a table or not found.
    public static func getElementColumnCount(windowUUID: String, viewID: Int) -> Int {
        return model.getElementColumnCount(windowUUID: windowUUID, viewID: viewID)
    }

    /// Returns all content rows for a table/list view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    /// - Returns: Array of string arrays representing rows, or nil if the view is not a table or not found.
    public static func getElementRows(windowUUID: String, viewID: Int) -> [[String]]? {
        return model.getElementRows(windowUUID: windowUUID, viewID: viewID)
    }

    /// Clears all content rows from a table/list view element, preserving column definitions.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    public static func clearElementRows(windowUUID: String, viewID: Int) {
        model.clearElementRows(windowUUID: windowUUID, viewID: viewID)
    }

    /// Replaces all content rows for a table/list view element.
    /// Clears the current selection if the selected row is no longer present.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - rows: Array of string arrays to set as the new content.
    public static func setElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        model.setElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
    }

    /// Appends rows to a table/list view element's existing content.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - rows: Array of string arrays to append.
    public static func appendElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        model.appendElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
    }

    /// Selects a row by its 0-based index in a Table/List element's content.
    /// An index outside 0..<rowCount clears the selection. Does not fire the element's actionID.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - index: 0-based row index to select.
    /// - Returns: The selected row's column values, or nil if the view is not a Table/List or the index was out of range.
    @discardableResult
    public static func selectElementRow(windowUUID: String, viewID: Int, index: Int) -> [String]? {
        return model.selectElementRow(windowUUID: windowUUID, viewID: viewID, index: index)
    }

    /// Selects the first row whose column value matches `text` (exact, case-sensitive).
    /// When `column` is nil, matches any column; otherwise matches the given 0-based column only.
    /// Does not fire the element's actionID.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - text: The text to match against a row's column value(s).
    ///   - column: 0-based column to match, or nil to match any column.
    /// - Returns: The 0-based index of the selected row, or nil if no row matched.
    @discardableResult
    public static func selectElementRow(windowUUID: String, viewID: Int, matching text: String, column: Int? = nil) -> Int? {
        return model.selectElementRow(windowUUID: windowUUID, viewID: viewID, matching: text, column: column)
    }

    /// Clears the current selection of a Table/List view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    public static func clearElementSelection(windowUUID: String, viewID: Int) {
        model.clearElementSelection(windowUUID: windowUUID, viewID: viewID)
    }

    /// Gets a structural property value for a view element by property name.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - propertyName: The property key (e.g., "columns", "widths", "disabled").
    /// - Returns: The property value, or nil if not found.
    public static func getElementProperty(windowUUID: String, viewID: Int, propertyName: String) -> Any? {
        return model.getElementProperty(windowUUID: windowUUID, viewID: viewID, propertyName: propertyName)
    }

    /// Sets a structural property value for a view element by property name.
    /// The value is re-validated through the element's validateProperties function.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - propertyName: The property key (e.g., "columns", "widths", "disabled").
    ///   - value: The new property value.
    public static func setElementProperty(windowUUID: String, viewID: Int, propertyName: String, value: Any) {
        model.setElementProperty(windowUUID: windowUUID, viewID: viewID, propertyName: propertyName, value: value)
    }

    /// Returns a dictionary mapping user-assigned (positive) view IDs to their view type strings for a given window.
    /// Auto-assigned negative IDs and ID 0 are excluded.
    /// - Parameter windowUUID: Unique identifier for the window.
    /// - Returns: Dictionary of [viewID: elementType] for all user-assigned views.
    public static func getElementInfo(windowUUID: String) -> [Int: String] {
        return model.getElementInfo(windowUUID: windowUUID)
    }

    /// Registers an action handler for a specific actionID.
    /// - Parameters:
    ///   - actionID: Identifier for the action (e.g., "button.click").
    ///   - handler: Closure to execute when the action is triggered, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    public static func registerActionHandler(actionID: String, handler: @escaping (String, String, Int, Int, Any?) -> Void) {
        model.registerActionHandler(for: actionID, handler: handler)
    }
    
    /// Unregisters an action handler for a specific actionID.
    /// - Parameter actionID: Identifier for the action to unregister.
    public static func unregisterActionHandler(actionID: String) {
        model.unregisterActionHandler(for: actionID)
    }
    
    /// Sets a default action handler for unregistered actionIDs.
    /// - Parameter handler: Closure to execute for unmatched actions, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    public static func setDefaultActionHandler(_ handler: @escaping (String, String, Int, Int, Any?) -> Void) {
        model.setDefaultActionHandler(handler)
    }
    
    /// Removes the default action handler.
    public static func removeDefaultActionHandler() {
        model.removeDefaultActionHandler()
    }

    // MARK: - Runtime Structural Mutations

    /// Inserts a new element into a flat container identified by parentID.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - parentID: The id of the container element that accepts insertions.
    ///   - dict: Element definition as a `[String: Any]` dictionary (same shape as a JSON element object).
    ///   - container: Container name (e.g. `"children"`, `"destinations"`). Omit when the container has exactly one flat container.
    ///   - position: Where to place the new element. Defaults to `.append`.
    /// - Returns: The inserted element's id.
    /// - Throws: `InsertError` describing what went wrong.
    @discardableResult
    public static func insertElement(windowUUID: String, parentID: Int, dict: [String: Any], container: String? = nil, position: ActionUI.InsertPosition = .append) throws -> Int {
        try model.insertElement(windowUUID: windowUUID, parentID: parentID, dict: dict, container: container, position: position)
    }

    /// JSON-string convenience wrapper around `insertElement(dict:)`.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - parentID: The id of the container element.
    ///   - json: A JSON string encoding one element object (e.g. `{"id":5,"type":"Text",...}`).
    ///   - container: Container name. Omit when the container has exactly one flat container.
    ///   - position: Where to place the new element. Defaults to `.append`.
    /// - Returns: The inserted element's id.
    /// - Throws: `InsertError` describing what went wrong.
    @discardableResult
    public static func insertElement(windowUUID: String, parentID: Int, json: String, container: String? = nil, position: ActionUI.InsertPosition = .append) throws -> Int {
        try model.insertElement(windowUUID: windowUUID, parentID: parentID, json: json, container: container, position: position)
    }

    /// Inserts a new row of cells into a Grid-style `rows` container identified by parentID.
    /// Rows have no addressable identity — use `.append`, `.prepend`, or `.at(_:)` for position;
    /// `.before`/`.after` are not valid for row containers.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - parentID: The id of the Grid element.
    ///   - cells: Array of cell dictionaries, each defining one cell element.
    ///   - container: Container name. Omit when the container has exactly one rows container.
    ///   - position: Where to insert the row. Defaults to `.append`.
    /// - Returns: The inserted cells' ids in order.
    /// - Throws: `InsertError` describing what went wrong.
    @discardableResult
    public static func insertRow(windowUUID: String, parentID: Int, cells: [[String: Any]], container: String? = nil, position: ActionUI.InsertPosition = .append) throws -> [Int] {
        try model.insertRow(windowUUID: windowUUID, parentID: parentID, cells: cells, container: container, position: position)
    }

    /// JSON-string convenience wrapper around `insertRow(cells:)`.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - parentID: The id of the Grid element.
    ///   - json: A JSON string encoding an array of cell objects (e.g. `[{"id":5,"type":"Text",...}]`).
    ///   - container: Container name. Omit when the container has exactly one rows container.
    ///   - position: Where to insert the row. Defaults to `.append`.
    /// - Returns: The inserted cells' ids in order.
    /// - Throws: `InsertError` describing what went wrong.
    @discardableResult
    public static func insertRow(windowUUID: String, parentID: Int, json: String, container: String? = nil, position: ActionUI.InsertPosition = .append) throws -> [Int] {
        try model.insertRow(windowUUID: windowUUID, parentID: parentID, json: json, container: container, position: position)
    }

    /// Removes the element with `viewID` from its parent container.
    /// Refuses to remove the window's root element. Cascade-removes ViewModels for all descendants.
    ///
    /// Note on Grid rows: only individual cells (which carry ids) are addressable. A whole row
    /// has no synthetic id and cannot be removed via this method — remove each cell individually,
    /// or rebuild the parent.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: The id of the element to remove.
    /// - Throws: `InsertError` describing what went wrong.
    public static func removeElement(windowUUID: String, viewID: Int) throws {
        try model.removeElement(windowUUID: windowUUID, viewID: viewID)
    }

    // MARK: - Modal Presentation

    /// Presents a window-level modal sheet or full-screen cover loaded from JSON/plist data.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - data: Encoded JSON or plist data describing the modal's view hierarchy.
    ///   - format: `"json"` or `"plist"`.
    ///   - style: `.sheet` or `.fullScreenCover`.
    ///   - onDismissActionID: Optional actionID fired when the modal is dismissed.
    public static func presentModal(windowUUID: String, data: Data, format: String, style: ActionUI.ModalStyle, onDismissActionID: String? = nil) throws {
        try model.presentModal(windowUUID: windowUUID, data: data, format: format, style: style, onDismissActionID: onDismissActionID)
    }

    /// Dismisses the active window-level modal for the given window.
    /// - Parameter windowUUID: Unique identifier for the window.
    public static func dismissModal(windowUUID: String) {
        model.dismissModal(windowUUID: windowUUID)
    }

    /// Presents a window-level alert dialog.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - title: Alert title.
    ///   - message: Optional alert message.
    ///   - buttons: Optional array of `DialogButton`; defaults to a single OK/cancel button if nil.
    public static func presentAlert(windowUUID: String, title: String, message: String? = nil, buttons: [ActionUI.DialogButton]? = nil) {
        if let buttons {
            model.presentAlert(windowUUID: windowUUID, title: title, message: message, buttons: buttons)
        } else {
            model.presentAlert(windowUUID: windowUUID, title: title, message: message)
        }
    }

    /// Presents a window-level confirmation dialog (action sheet style on iOS).
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - title: Dialog title.
    ///   - message: Optional dialog message.
    ///   - buttons: Array of `DialogButton` defining the available choices.
    public static func presentConfirmationDialog(windowUUID: String, title: String, message: String? = nil, buttons: [ActionUI.DialogButton]) {
        model.presentConfirmationDialog(windowUUID: windowUUID, title: title, message: message, buttons: buttons)
    }

    /// Dismisses the active window-level alert or confirmation dialog for the given window.
    /// - Parameter windowUUID: Unique identifier for the window.
    public static func dismissDialog(windowUUID: String) {
        model.dismissDialog(windowUUID: windowUUID)
    }

    /// Loads a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: A SwiftUI view loaded from the description.
    /// Design decision: Determines local vs. remote based on URL scheme; uses FileLoadableView for local (sync) and RemoteLoadableView for remote (async with ProgressView).
    public static func loadView(from url: URL, windowUUID: String, isContentView: Bool) -> any SwiftUI.View {
        let logger = model.logger
        if url.scheme == "file" {
            return ActionUI.FileLoadableView(fileURL: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        } else {
            return ActionUI.RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        }
    }
    
    #if canImport(AppKit)
    /// Loads an NSHostingController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: An NSHostingController with the loaded SwiftUI view embedded as its root view.
    /// Design decision: Wraps the view from loadView in an NSHostingController for macOS integration.
    public static func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> NSHostingController<AnyView> {
        let view = loadView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        return NSHostingController(rootView: AnyView(view))
    }
    #endif // canImport(AppKit)
    
    #if canImport(UIKit)
    /// Loads a UIHostingController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: A UIHostingController with the loaded SwiftUI view embedded as its root view.
    /// Design decision: Wraps the view from loadView in a UIHostingController for iOS/iPadOS/tvOS/visionOS/watchOS integration.
    public static func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> UIHostingController<AnyView> {
        let view = loadView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        return UIHostingController(rootView: AnyView(view))
    }
    #endif // canImport(UIKit)
}
