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
    ///   - value: The value to set, matching the view's expected type.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    public static func setElementValue(windowUUID: String, viewID: Int, value: Any, viewPartID: Int = 0) {
        model.setElementValue(windowUUID: windowUUID, viewID: viewID, value: value, viewPartID: viewPartID)
    }
    
    /// Sets the value of a view element from a string representation, parsing it to the view's expected type.
    /// Supports ISO 8601 for Date, JSON for CLLocationCoordinate2D, and other type conversions per ActionUIModel.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: String representation of the value.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    public static func setElementValueFromString(windowUUID: String, viewID: Int, value: String, viewPartID: Int = 0) {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: viewID, value: value, viewPartID: viewPartID)
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
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: String representation of the value, or nil if not found or invalid.
    public static func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> String? {
        return model.getElementValueAsString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
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
