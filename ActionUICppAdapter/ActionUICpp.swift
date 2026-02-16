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
    @MainActor public static func setElementValue(windowUUID: String, viewID: Int, value: Any, viewPartID: Int = 0) {
        model.setElementValue(windowUUID: windowUUID, viewID: viewID, value: value, viewPartID: viewPartID)
    }
    
    /// Sets the value of a view element from a string representation, parsing it to the view's expected type.
    /// Supports ISO 8601 for Date, JSON for CLLocationCoordinate2D, and other type conversions per ActionUIModel.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: String representation of the value.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    @MainActor public static func setElementValueFromString(windowUUID: String, viewID: Int, value: String, viewPartID: Int = 0) {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: viewID, value: value, viewPartID: viewPartID)
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
    /// - Returns: String representation of the value, or nil if not found or invalid.
    @MainActor public static func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> String? {
        return model.getElementValueAsString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
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
