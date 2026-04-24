// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUICpp.swift
//  ActionUICppAdapter
//
//  This is a proof of concept but it doesn't look like Swift -> C++ bridge is good enough to make it usable
//  The generated -Swift.h is missing member methods because of unsupported features used
//  Also, the implementations here don't have any code ensuring @MainActor isolation

import ActionUI
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Action handler closure type for C++ with Swift-native types.
/// Design decision: Closure type maps to std::function<void(std::string, std::string, int, int, std::optional<std::any>)> in C++ via interoperability.
/// No explicit parameter names needed, as C++ calls will use positional arguments.
public typealias ActionUICppActionHandler = (String, String, Int, Int, Any?) -> Void

/// Logger closure type for C++.
/// Design decision: Closure type maps to std::function<void(std::string, int)> in C++, avoiding protocol interoperability issues.
public typealias ActionUICppLogger = (String, Int) -> Void

/// Adapter struct to conform to ActionUILogger protocol, wrapping the C++-compatible ActionUICppLogger closure.
private struct CppLoggerAdapter: ActionUILogger {
    let closure: ActionUICppLogger
    
    func log(_ message: String, _ level: ActionUI.LoggerLevel) {
        closure(message, level.rawValue)
    }
}

/// Public entry point for the ActionUI C++ adapter, providing a simplified, static API to interact with the core ActionUI library.
/// Implemented in Swift for C++ compatibility via Swift-C++ interoperability.
/// Design decision: Uses struct with static methods to mirror ActionUISwift adapter.
/// Action handlers and logger use closures, bridged to std::function in C++.
/// All methods are @MainActor to align with ActionUIModel's concurrency model.
/// Note: Any parameters/returns require handling with Swift runtime types in C++; std::any can be used on C++ side.
public struct ActionUICpp {
    @MainActor private static let model = ActionUIModel.shared
    
    /// Sets a custom logger for ActionUI to handle debugging and error reporting.
    /// - Parameter logger: A closure to invoke for logging, receiving message and level (rawValue of ActionUI.LoggerLevel).
    @MainActor public static func setLogger(_ logger: @escaping ActionUICppLogger) {
        model.logger = CppLoggerAdapter(closure: logger)
    }
    
    /// Sets the value of a view element identified by viewID in the specified window.
    /// Supports various value types as defined by the view's valueType in ActionUIRegistry.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: The value to set, matching the view's expected type.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    @MainActor public static func setElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0, value: Any) {
        model.setElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: value)
    }
    
    /// Sets the value of a view element from a string representation, parsing it to the view's expected type.
    /// Supports ISO 8601 for Date, JSON for CLLocationCoordinate2D, and other type conversions per ActionUIModel.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    ///   - value: String representation of the value.
    ///   - contentType: Optional hint for parsing rich-text content ("plain", "markdown", "html", "rtf", "json"). Pass nil for default behavior.
    @MainActor public static func setElementValueFromString(windowUUID: String, viewID: Int, viewPartID: Int = 0, value: String, contentType: String? = nil) {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: value, contentType: contentType)
    }

    /// Gets the value of a view element identified by viewID in the specified window.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: The value of the view element, or nil if not found or invalid.
    @MainActor public static func getElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> Any? {
        return model.getElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
    }
    
    /// Gets the string representation of a view element's value.
    /// Uses type-specific formatting (e.g., ISO 8601 for Date, JSON for CLLocationCoordinate2D).
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    ///   - contentType: Optional hint for serializing rich-text content ("plain", "json"). Pass nil for default behavior.
    /// - Returns: String representation of the value, or nil if not found or invalid.
    @MainActor public static func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0, contentType: String? = nil) -> String? {
        return model.getElementValueAsString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, contentType: contentType)
    }

    /// Returns the current value for a single state key of a view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key (e.g., "isLoading", "canGoBack").
    /// - Returns: The state value, or nil if the view or key is not found.
    @MainActor public static func getElementState(windowUUID: String, viewID: Int, key: String) -> Any? {
        return model.getElementState(windowUUID: windowUUID, viewID: viewID, key: key)
    }

    /// Returns the string representation of a single state value.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    /// - Returns: String representation, or nil if the view or key is not found.
    @MainActor public static func getElementStateAsString(windowUUID: String, viewID: Int, key: String) -> String? {
        return model.getElementStateAsString(windowUUID: windowUUID, viewID: viewID, key: key)
    }

    /// Sets a single state key to a new value.
    /// Rejects the update (with an error log) if the new value's type differs from the existing value's type.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    ///   - value: The new value. Must match the type of the existing value if the key already exists.
    @MainActor public static func setElementState(windowUUID: String, viewID: Int, key: String, value: Any) {
        model.setElementState(windowUUID: windowUUID, viewID: viewID, key: key, value: value)
    }

    /// Sets a single state key by parsing a string into the type of the existing value.
    /// If the key does not yet exist the string is stored as-is.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - key: The state key.
    ///   - value: String representation of the new value.
    @MainActor public static func setElementStateFromString(windowUUID: String, viewID: Int, key: String, value: String) {
        model.setElementStateFromString(windowUUID: windowUUID, viewID: viewID, key: key, value: value)
    }

    /// Returns the number of columns defined for a table/list view element.
    /// Returns 0 for non-table elements or if the view is not found.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    /// - Returns: Number of columns, or 0 if the view is not a table or not found.
    @MainActor public static func getElementColumnCount(windowUUID: String, viewID: Int) -> Int {
        return model.getElementColumnCount(windowUUID: windowUUID, viewID: viewID)
    }

    /// Returns all content rows for a table/list view element.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    /// - Returns: Array of string arrays representing rows, or nil if the view is not a table or not found.
    @MainActor public static func getElementRows(windowUUID: String, viewID: Int) -> [[String]]? {
        return model.getElementRows(windowUUID: windowUUID, viewID: viewID)
    }

    /// Clears all content rows from a table/list view element, preserving column definitions.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    @MainActor public static func clearElementRows(windowUUID: String, viewID: Int) {
        model.clearElementRows(windowUUID: windowUUID, viewID: viewID)
    }

    /// Replaces all content rows for a table/list view element.
    /// Clears the current selection if the selected row is no longer present.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - rows: Array of string arrays to set as the new content.
    @MainActor public static func setElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        model.setElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
    }

    /// Appends rows to a table/list view element's existing content.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - rows: Array of string arrays to append.
    @MainActor public static func appendElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        model.appendElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
    }

    /// Gets a structural property value for a view element by property name.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - propertyName: The property key (e.g., "columns", "widths", "disabled").
    /// - Returns: The property value, or nil if not found.
    @MainActor public static func getElementProperty(windowUUID: String, viewID: Int, propertyName: String) -> Any? {
        return model.getElementProperty(windowUUID: windowUUID, viewID: viewID, propertyName: propertyName)
    }

    /// Sets a structural property value for a view element by property name.
    /// The value is re-validated through the element's validateProperties function.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - propertyName: The property key (e.g., "columns", "widths", "disabled").
    ///   - value: The new property value.
    @MainActor public static func setElementProperty(windowUUID: String, viewID: Int, propertyName: String, value: Any) {
        model.setElementProperty(windowUUID: windowUUID, viewID: viewID, propertyName: propertyName, value: value)
    }

    /// Returns a dictionary mapping user-assigned (positive) view IDs to their view type strings for a given window.
    /// Auto-assigned negative IDs and ID 0 are excluded.
    /// - Parameter windowUUID: Unique identifier for the window.
    /// - Returns: Dictionary of [viewID: elementType] for all user-assigned views.
    @MainActor public static func getElementInfo(windowUUID: String) -> [Int: String] {
        return model.getElementInfo(windowUUID: windowUUID)
    }

    /// Registers an action handler for a specific actionID.
    /// - Parameters:
    ///   - actionID: Identifier for the action (e.g., "button.click").
    ///   - handler: Closure to execute when the action is triggered, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    @MainActor public static func registerActionHandler(actionID: String, handler: @escaping ActionUICppActionHandler) {
        model.registerActionHandler(for: actionID) { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
            handler(swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext)
        }
    }
    
    /// Unregisters an action handler for a specific actionID.
    /// - Parameter actionID: Identifier for the action to unregister.
    @MainActor public static func unregisterActionHandler(actionID: String) {
        model.unregisterActionHandler(for: actionID)
    }
    
    /// Sets a default action handler for unregistered actionIDs.
    /// - Parameter handler: Closure to execute for unmatched actions, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    @MainActor public static func setDefaultActionHandler(_ handler: @escaping ActionUICppActionHandler) {
        model.setDefaultActionHandler { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
            handler(swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext)
        }
    }
    
    /// Removes the default action handler.
    @MainActor public static func removeDefaultActionHandler() {
        model.removeDefaultActionHandler()
    }

    // MARK: - Modal Presentation

    /// Presents a window-level modal sheet or full-screen cover loaded from JSON/plist data.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - data: Encoded JSON or plist data describing the modal's view hierarchy.
    ///   - format: `"json"` or `"plist"`.
    ///   - style: `.sheet` or `.fullScreenCover`.
    ///   - onDismissActionID: Optional actionID fired when the modal is dismissed.
    @MainActor public static func presentModal(windowUUID: String, data: Data, format: String, style: ActionUI.ModalStyle, onDismissActionID: String? = nil) throws {
        try model.presentModal(windowUUID: windowUUID, data: data, format: format, style: style, onDismissActionID: onDismissActionID)
    }

    /// Dismisses the active window-level modal for the given window.
    /// - Parameter windowUUID: Unique identifier for the window.
    @MainActor public static func dismissModal(windowUUID: String) {
        model.dismissModal(windowUUID: windowUUID)
    }

    /// Presents a window-level alert dialog.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - title: Alert title.
    ///   - message: Optional alert message.
    ///   - buttons: Optional array of `DialogButton`; defaults to a single OK/cancel button if nil.
    @MainActor public static func presentAlert(windowUUID: String, title: String, message: String? = nil, buttons: [ActionUI.DialogButton]? = nil) {
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
    @MainActor public static func presentConfirmationDialog(windowUUID: String, title: String, message: String? = nil, buttons: [ActionUI.DialogButton]) {
        model.presentConfirmationDialog(windowUUID: windowUUID, title: title, message: message, buttons: buttons)
    }

    /// Dismisses the active window-level alert or confirmation dialog for the given window.
    /// - Parameter windowUUID: Unique identifier for the window.
    @MainActor public static func dismissDialog(windowUUID: String) {
        model.dismissDialog(windowUUID: windowUUID)
    }

    #if canImport(AppKit)
    /// Loads an NSView hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// Available only on macOS.
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: An NSView (specifically, NSHostingView) with the loaded SwiftUI view embedded. If the URL or data is invalid, the view displays an error message.
    /// Design decision: Returns NSView for compatibility; assumes C++ client uses Objective-C++ for AppKit integration. Non-optional return reflects guaranteed view creation, with errors surfaced as view content.
    @MainActor public static func loadView(from url: URL, windowUUID: String, isContentView: Bool) -> NSView {
        let swiftView = loadActionUIView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        let hostingView = NSHostingView(rootView: AnyView(swiftView))
        hostingView.autoresizingMask = [.width, .height]
        return hostingView
    }
    #endif
    
    #if canImport(AppKit)
    /// Loads an NSViewController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: An NSViewController (specifically, NSHostingController) with the loaded SwiftUI view embedded as its root view. If the URL or data is invalid, the view displays an error message.
    /// Design decision: Returns NSViewController for compatibility; assumes C++ client uses Objective-C++ for AppKit integration. Non-optional return reflects guaranteed controller creation, with errors surfaced as view content.
    @MainActor public static func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> NSViewController {
        let swiftView = loadActionUIView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        let hostingController = NSHostingController(rootView: AnyView(swiftView))
        hostingController.view.autoresizingMask = [.width, .height]
        return hostingController
    }
    #endif
    
    #if canImport(UIKit)
    /// Loads a UIViewController hosting a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// - Parameters:
    ///   - url: The URL to the JSON or plist description file (file:// for local, http:// or https:// for remote).
    ///   - windowUUID: Unique identifier for the window.
    ///   - isContentView: If true, loads as the root view of the window; if false, loads as a subview without overwriting the root element.
    /// - Returns: A UIViewController (specifically, UIHostingController) with the loaded SwiftUI view embedded as its root view. If the URL or data is invalid, the view displays an error message.
    /// Design decision: Returns UIViewController for compatibility; assumes C++ client uses Objective-C++ for UIKit integration. Non-optional return reflects guaranteed controller creation, with errors surfaced as view content.
    @MainActor public static func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> UIViewController {
        let swiftView = loadActionUIView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        let hostingController = UIHostingController(rootView: AnyView(swiftView))
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return hostingController
    }
    #endif
    
    /// Internal helper to load the SwiftUI view, used by loadView and loadHostingController.
    /// Not exposed to C++; handles local/remote loading.
    /// Design decision: Mirrors ActionUISwift.loadView for consistency, using FileLoadableView or RemoteLoadableView based on URL scheme. Always returns a valid view, with errors displayed as view content.
    @MainActor private static func loadActionUIView(from url: URL, windowUUID: String, isContentView: Bool) -> any SwiftUI.View {
        let logger = model.logger
        if url.scheme == "file" {
            return ActionUI.FileLoadableView(fileURL: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        } else {
            return ActionUI.RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        }
    }
}
