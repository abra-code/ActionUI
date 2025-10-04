//
//  ActionUISwift.swift
//  ActionUISwiftAdapter
//

import ActionUI
import Foundation

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
        model.setLogger(logger)
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
}
