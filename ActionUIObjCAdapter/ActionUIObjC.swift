//
//  ActionUIObjC.swift
//  ActionUIObjCAdapter
//

import ActionUI
import Foundation

/// Objective-C compatible logger protocol for bridging to ActionUILogger.
/// Design decision: Defined in adapter to avoid modifying core ActionUI, allowing Obj-C clients to implement logging without @objc in core protocol.
@objc public protocol ActionUIObjCLogger {
    @objc func logMessage(_ message: NSString, level: NSInteger)
}

/// Private bridge class to convert ActionUIObjCLogger to ActionUILogger.
private class ObjCLoggerBridge: ActionUILogger {
    let objCLogger: any ActionUIObjCLogger
    
    init(objCLogger: any ActionUIObjCLogger) {
        self.objCLogger = objCLogger
    }
    
    func log(_ message: String, _ level: Level) {
        objCLogger.logMessage(message as NSString, level: level.rawValue)
    }
}

/// Action handler block type for Objective-C with explicit parameter names.
/// Design decision: Named parameters improve readability in the generated Objective-C header.
/// No @objc attribute, as Swift automatically bridges this closure type to an Objective-C block in @objc methods.
public typealias ActionUIObjCActionHandlerBlock = (_ actionID: NSString, _ windowUUID: NSString, _ viewID: NSInteger, _ viewPartID: NSInteger, _ context: Any?) -> Void

/// Public entry point for the ActionUI Objective-C adapter, providing a simplified, static API to interact with the core ActionUI library.
/// Implemented in Swift with @objc annotations for Objective-C compatibility.
/// Design decision: Uses class methods (+) to mirror the static methods in ActionUISwift adapter.
/// Action handlers use Objective-C blocks, bridged to Swift closures for ActionUIModel.
/// Logger uses a bridged protocol to maintain modularity without altering core ActionUI.
/// All methods are @MainActor to align with ActionUIModel's concurrency model.
@objc public class ActionUIObjC: NSObject {
    @MainActor private static let model = ActionUIModel.shared
    
    /// Sets a custom logger for ActionUI to handle debugging and error reporting.
    /// - Parameter logger: A client-provided logger conforming to ActionUIObjCLogger.
    @MainActor @objc public class func setLogger(_ logger: any ActionUIObjCLogger) {
        model.logger = ObjCLoggerBridge(objCLogger: logger)
    }
    
    /// Sets the value of a view element identified by viewID in the specified window.
    /// Supports various value types as defined by the view's valueType in ActionUIRegistry.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: The value to set, matching the view's expected type.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    @MainActor @objc public class func setElementValueWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, value: Any, viewPartID: NSInteger) {
        model.setElementValue(windowUUID: windowUUID as String, viewID: Int(viewID), value: value, viewPartID: Int(viewPartID))
    }
    
    /// Sets the value of a view element from a string representation, parsing it to the view's expected type.
    /// Supports ISO 8601 for Date, JSON for CLLocationCoordinate2D, and other type conversions per ActionUIModel.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - value: String representation of the value.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    @MainActor @objc public class func setElementValueFromStringWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, value: NSString, viewPartID: NSInteger) {
        model.setElementValueFromString(windowUUID: windowUUID as String, viewID: Int(viewID), value: value as String, viewPartID: Int(viewPartID))
    }
    
    /// Gets the value of a view element identified by viewID in the specified window.
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: The value of the view element, or nil if not found or invalid.
    @MainActor @objc public class func getElementValueWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, viewPartID: NSInteger) -> Any? {
        return model.getElementValue(windowUUID: windowUUID as String, viewID: Int(viewID), viewPartID: Int(viewPartID))
    }
    
    /// Gets the string representation of a view element's value.
    /// Uses type-specific formatting (e.g., ISO 8601 for Date, JSON for CLLocationCoordinate2D).
    /// - Parameters:
    ///   - windowUUID: Unique identifier for the window.
    ///   - viewID: Unique identifier for the view element.
    ///   - viewPartID: Optional part identifier (e.g., for multi-column tables; defaults to 0).
    /// - Returns: String representation of the value, or nil if not found or invalid.
    @MainActor @objc public class func getElementValueAsStringWithWindowUUID(_ windowUUID: NSString, viewID: NSInteger, viewPartID: NSInteger) -> NSString? {
        return model.getElementValueAsString(windowUUID: windowUUID as String, viewID: Int(viewID), viewPartID: Int(viewPartID)) as NSString?
    }
    
    /// Registers an action handler for a specific actionID.
    /// - Parameters:
    ///   - actionID: Identifier for the action (e.g., "button.click").
    ///   - handler: Block to execute when the action is triggered, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    @MainActor @objc public class func registerActionHandlerForActionID(_ actionID: NSString, handler: @escaping ActionUIObjCActionHandlerBlock) {
        model.registerActionHandler(for: actionID as String) { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
            handler(swiftActionID as NSString, swiftWindowUUID as NSString, NSInteger(swiftViewID), NSInteger(swiftViewPartID), swiftContext)
        }
    }
    
    /// Unregisters an action handler for a specific actionID.
    /// - Parameter actionID: Identifier for the action to unregister.
    @MainActor @objc public class func unregisterActionHandlerForActionID(_ actionID: NSString) {
        model.unregisterActionHandler(for: actionID as String)
    }
    
    /// Sets a default action handler for unregistered actionIDs.
    /// - Parameter handler: Block to execute for unmatched actions, receiving actionID, windowUUID, viewID, viewPartID, and optional context.
    @MainActor @objc public class func setDefaultActionHandler(_ handler: @escaping ActionUIObjCActionHandlerBlock) {
        model.setDefaultActionHandler { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
            handler(swiftActionID as NSString, swiftWindowUUID as NSString, NSInteger(swiftViewID), NSInteger(swiftViewPartID), swiftContext)
        }
    }
    
    /// Removes the default action handler.
    @MainActor @objc public class func removeDefaultActionHandler() {
        model.removeDefaultActionHandler()
    }
}
