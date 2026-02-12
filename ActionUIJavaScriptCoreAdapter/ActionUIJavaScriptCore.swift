//
//  ActionUIJavaScriptCore.swift
//  ActionUIJavaScriptCoreAdapter
//

import ActionUI
import Foundation
import JavaScriptCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// JavaScript API Documentation
///
/// The `ActionUIJavaScriptCore` adapter uses a JavaScriptCore to run JavaScript and exposes a global `ActionUI` object in the JavaScript context, providing the following methods for interacting with the ActionUI library:
///
/// - `setLogger(loggerFunction)`
///   - Parameters:
///     - `loggerFunction`: Function - A function that receives a message (string) and level (number, corresponding to `ActionUI.LoggerLevel` raw values: 1=error, 2=warning, 3=info, 4=debug, 5=verbose).
///       - `error` (1): Indicates a critical issue that may prevent normal operation (e.g., invalid JSON causing view rendering failure).
///       - `warning` (2): Indicates a non-critical issue that may affect functionality (e.g., missing optional property with a fallback).
///       - `info` (3): Indicates general information for debugging or tracking (e.g., view registration or state update).
///       - `debug` (4): Indicates detailed debugging information for developers (e.g., intermediate state changes or binding updates).
///       - `verbose` (5): Indicates exhaustive diagnostic information (e.g., every property validation or view construction step).
///   - Description: Sets a custom logger function to handle debugging and error reporting.
///   - Example: `ActionUI.setLogger(function(message, level) { console.log("[Level " + level + "] " + message); });`
///
/// - `setElementValue(windowUUID, viewID, value, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `value`: Any - The value to set, matching the view's expected type (e.g., String, Number, Boolean, Object, Array).
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Description: Sets the value of a view element identified by `viewID` in the specified `windowUUID`.
///   - Example: `ActionUI.setElementValue("window-12345", 2, "New text", 0);`
///
/// - `setElementValueFromString(windowUUID, viewID, value, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `value`: String - The string representation of the value, parsed to the view's expected type (e.g., ISO 8601 for Date).
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Description: Sets the value of a view element from a string representation.
///   - Example: `ActionUI.setElementValueFromString("window-12345", 2, "2023-10-05T12:00:00Z", 0);`
///
/// - `getElementValue(windowUUID, viewID, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Returns: Any - The value as a JavaScript-compatible type (e.g., String, Number, Object, Array), or `undefined` if not found.
///   - Description: Retrieves the value of a view element.
///   - Example: `let value = ActionUI.getElementValue("window-12345", 2, 0);`
///
/// - `getElementValueAsString(windowUUID, viewID, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Returns: String - The string representation of the view element's value (e.g., ISO 8601 for Date), or `undefined` if not found.
///   - Description: Retrieves the string representation of a view element's value.
///   - Example: `let stringValue = ActionUI.getElementValueAsString("window-12345", 2, 0);`
///
/// - `registerActionHandler(actionID, handlerFunction)`
///   - Parameters:
///     - `actionID`: String - Identifier for the action (e.g., "button.click").
///     - `handlerFunction`: Function - A function to execute when the action is triggered, receiving `actionID` (String), `windowUUID` (String), `viewID` (Number), `viewPartID` (Number), and `context` (Any, null if absent).
///   - Description: Registers a handler for a specific action ID.
///   - Example: `ActionUI.registerActionHandler("button.click", function(actionID, windowUUID, viewID, viewPartID, context) { console.log("Action: " + actionID); });`
///
/// - `unregisterActionHandler(actionID)`
///   - Parameters:
///     - `actionID`: String - Identifier for the action (e.g., "button.click").
///   - Description: Unregisters a handler for a specific action ID.
///   - Example: `ActionUI.unregisterActionHandler("button.click");`
///
/// - `setDefaultActionHandler(handlerFunction)`
///   - Parameters:
///     - `handlerFunction`: Function - A function for unmatched actions, receiving `actionID` (String), `windowUUID` (String), `viewID` (Number), `viewPartID` (Number), and `context` (Any, null if absent).
///   - Description: Sets a default handler for unregistered action IDs.
///   - Example: `ActionUI.setDefaultActionHandler(function(actionID, windowUUID, viewID, viewPartID, context) { console.log("Default: " + actionID); });`
///
/// - `removeDefaultActionHandler()`
///   - Parameters: None
///   - Description: Removes the default action handler.
///   - Example: `ActionUI.removeDefaultActionHandler();`
///
/// Design decision: These APIs mirror the `ActionUISwift` and `ActionUIObjC` adapters, with JavaScript-compatible types (e.g., Number for viewID, Any for values). The adapter does not return native views/controllers to JavaScript or expose internal model operations like loadDescription. Instead, Swift host code uses `loadView` or `loadHostingController` to render the UI after JavaScript interactions, typically with a JSON or plist description provided via the host.
/// App Store compliance: JavaScript is interpreted via JavaScriptCore (no JIT); scripts must be bundled or loaded as non-executable data.

/// Objective-C compatible logger protocol for JavaScript bridging, but since JavaScript uses functions, we use a JSValue-based bridge.
/// Design decision: Allows JavaScript to provide a logger function that gets called with message and level.
private class JSLoggerBridge: ActionUILogger {
    let loggerFunction: JSValue
    
    init(loggerFunction: JSValue) {
        self.loggerFunction = loggerFunction
    }
    
    func log(_ message: String, _ level: LoggerLevel) {
        _ = loggerFunction.call(withArguments: [message, level.rawValue])
    }
}

/// Action handler closure type for JavaScript, using JSValue for the handler function.
/// Design decision: JavaScript handlers are functions that get invoked with actionID, windowUUID, viewID, viewPartID, context.
public typealias ActionUIJavaScriptActionHandler = JSValue

/// Public entry point for the ActionUI JavaScript adapter, providing a bridge to interact with the core ActionUI library from JavaScript code via JavaScriptCore.
/// Implemented as a class to manage the JSContext instance, exposing an "ActionUI" object in JavaScript with methods mirroring the common adapter API.
/// Design decision: Uses instance-based JSContext to allow multiple isolated contexts if needed; exposes functions as properties on a global "ActionUI" object.
/// Action handlers are JavaScript functions bridged to Swift closures for ActionUIModel.
/// All bridging operations are @MainActor to align with ActionUIModel's concurrency model.
/// Does not return native views/controllers to JavaScript; instead, provides Swift methods like loadHostingController for host-side integration after JavaScript has loaded descriptions.
/// App Store compliance: Relies on interpreted JavaScriptCore (no JIT); users must bundle scripts or load data non-executably.
@MainActor
public class ActionUIJavaScriptCore {
    public let context: JSContext
    
    /// Static reference to the shared ActionUIModel singleton.
    /// Design decision: Static to ensure all instances of ActionUIJavaScriptCore interact with the same model, aligning with the singleton pattern of ActionUIModel.shared and the design of other adapters (ActionUISwift, ActionUIObjC). This maintains consistency of UI state across multiple JavaScript contexts.
    private static let model = ActionUIModel.shared
    
    public init() {
        context = JSContext()!
        
        // Set up exception handler
        context.exceptionHandler = { context, exception in
            print("JavaScript Error: \(exception?.toString() ?? "Unknown error")")
        }
        
        // Create the global ActionUI object
        let actionUIObject = JSValue(newObjectIn: context)!
        
        // Set up individual API methods
        setupLogger(actionUIObject: actionUIObject)
        setupElementValueMethods(actionUIObject: actionUIObject)
        setupActionHandlerMethods(actionUIObject: actionUIObject)
        
        // Set the global ActionUI object
        context.setObject(actionUIObject, forKeyedSubscript: "ActionUI" as NSString)
    }
    
    // MARK: - API Setup Helpers
    
    private func setupLogger(actionUIObject: JSValue) {
        // setLogger(loggerFunction) - loggerFunction is a JS function(message, level)
        let setLogger: @convention(block) (JSValue) -> Void = { loggerFunction in
            if loggerFunction.isObject {
                let bridge = JSLoggerBridge(loggerFunction: loggerFunction)
                ActionUIJavaScriptCore.model.logger = bridge
            }
        }
        actionUIObject.setValue(setLogger, forProperty: "setLogger")
    }
    
    private func setupElementValueMethods(actionUIObject: JSValue) {
        // setElementValue(windowUUID, viewID, value, viewPartID)
        let setElementValue: @convention(block) (String, Double, JSValue, Double) -> Void = { windowUUID, viewID, jsValue, viewPartID in
            // Design decision: Use JSValue.toObject() to convert JavaScript values to Swift objects (e.g., String, Double, NSDictionary).
            // Avoid toObjectOf(_:) as it requires an Objective-C class type, not suitable for generic Any conversion.
            let value = jsValue.toObject() ?? NSNull()
            ActionUIJavaScriptCore.model.setElementValue(windowUUID: windowUUID, viewID: Int(viewID), value: value, viewPartID: Int(viewPartID))
        }
        actionUIObject.setValue(setElementValue, forProperty: "setElementValue")
        
        // setElementValueFromString(windowUUID, viewID, value, viewPartID)
        let setElementValueFromString: @convention(block) (String, Double, String, Double) -> Void = { windowUUID, viewID, value, viewPartID in
            ActionUIJavaScriptCore.model.setElementValueFromString(windowUUID: windowUUID, viewID: Int(viewID), value: value, viewPartID: Int(viewPartID))
        }
        actionUIObject.setValue(setElementValueFromString, forProperty: "setElementValueFromString")
        
        // getElementValue(windowUUID, viewID, viewPartID) -> value
        let getElementValue: @convention(block) (String, Double, Double) -> JSValue = { windowUUID, viewID, viewPartID in
            let value = ActionUIJavaScriptCore.model.getElementValue(windowUUID: windowUUID, viewID: Int(viewID), viewPartID: Int(viewPartID))
            return JSValue(object: value, in: self.context)
        }
        actionUIObject.setValue(getElementValue, forProperty: "getElementValue")
        
        // getElementValueAsString(windowUUID, viewID, viewPartID) -> string
        let getElementValueAsString: @convention(block) (String, Double, Double) -> String? = { windowUUID, viewID, viewPartID in
            return ActionUIJavaScriptCore.model.getElementValueAsString(windowUUID: windowUUID, viewID: Int(viewID), viewPartID: Int(viewPartID))
        }
        actionUIObject.setValue(getElementValueAsString, forProperty: "getElementValueAsString")
    }
    
    private func setupActionHandlerMethods(actionUIObject: JSValue) {
        // registerActionHandler(actionID, handlerFunction) - handlerFunction(actionID, windowUUID, viewID, viewPartID, context)
        let registerActionHandler: @convention(block) (String, JSValue) -> Void = { actionID, handlerFunction in
            if handlerFunction.isObject {
                let swiftHandler: (String, String, Int, Int, Any?) -> Void = { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
                    _ = handlerFunction.call(withArguments: [swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext ?? NSNull()])
                }
                ActionUIJavaScriptCore.model.registerActionHandler(for: actionID, handler: swiftHandler)
            }
        }
        actionUIObject.setValue(registerActionHandler, forProperty: "registerActionHandler")
        
        // unregisterActionHandler(actionID)
        let unregisterActionHandler: @convention(block) (String) -> Void = { actionID in
            ActionUIJavaScriptCore.model.unregisterActionHandler(for: actionID)
        }
        actionUIObject.setValue(unregisterActionHandler, forProperty: "unregisterActionHandler")
        
        // setDefaultActionHandler(handlerFunction) - handlerFunction(actionID, windowUUID, viewID, viewPartID, context)
        let setDefaultActionHandler: @convention(block) (JSValue) -> Void = { handlerFunction in
            if handlerFunction.isObject {
                let swiftHandler: (String, String, Int, Int, Any?) -> Void = { swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext in
                    _ = handlerFunction.call(withArguments: [swiftActionID, swiftWindowUUID, swiftViewID, swiftViewPartID, swiftContext ?? NSNull()])
                }
                ActionUIJavaScriptCore.model.setDefaultActionHandler(swiftHandler)
            }
        }
        actionUIObject.setValue(setDefaultActionHandler, forProperty: "setDefaultActionHandler")
        
        // removeDefaultActionHandler()
        let removeDefaultActionHandler: @convention(block) () -> Void = {
            ActionUIJavaScriptCore.model.removeDefaultActionHandler()
        }
        actionUIObject.setValue(removeDefaultActionHandler, forProperty: "removeDefaultActionHandler")
    }
    
    // MARK: - Swift-side Loading Methods (mirroring ActionUISwift)
    
    /// Loads a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// Design decision: Provided for Swift host code to load views after JavaScript has potentially interacted with the model (e.g., set values or handlers).
    public func loadView(from url: URL, windowUUID: String, isContentView: Bool) -> any SwiftUI.View {
        let logger = ActionUIJavaScriptCore.model.logger
        if url.scheme == "file" {
            return ActionUI.FileLoadableView(fileURL: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        } else {
            return ActionUI.RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, logger: logger)
        }
    }
    
    #if canImport(AppKit)
    /// Loads an NSHostingController hosting a SwiftUI view from a JSON or plist description at the given URL.
    public func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> NSHostingController<AnyView> {
        let view = loadView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        return NSHostingController(rootView: AnyView(view))
    }
    #endif
    
    #if canImport(UIKit)
    /// Loads a UIHostingController hosting a SwiftUI view from a JSON or plist description at the given URL.
    public func loadHostingController(from url: URL, windowUUID: String, isContentView: Bool) -> UIHostingController<AnyView> {
        let view = loadView(from: url, windowUUID: windowUUID, isContentView: isContentView)
        return UIHostingController(rootView: AnyView(view))
    }
    #endif
}
