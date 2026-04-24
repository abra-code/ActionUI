//
//  ActionUIWebKitJS.swift
//  ActionUIWebKitJSAdapter
//

import ActionUI
import Foundation
import WebKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// JavaScript API Documentation
///
/// The `ActionUIWebKitJS` adapter uses a WKWebView to run JavaScript and exposes a global `ActionUI` object in the JavaScript context, providing the following methods for interacting with the ActionUI library. Methods that return values are asynchronous (returning Promises) due to the WebKit bridge's nature.
///
/// - `setLogger(loggerFunction)`
///   - Parameters:
///     - `loggerFunction`: Function - A function that receives a message (string) and level (number, corresponding to `ActionUI.LoggerLevel` raw values: 1=error, 2=warning, 3=info, 4=debug, 5=verbose).
///       - `error` (1): Indicates a critical issue that may prevent normal operation (e.g., invalid JSON causing view rendering failure).
///       - `warning` (2): Indicates a non-critical issue that may affect functionality (e.g., missing optional property with a fallback).
///       - `info` (3): Indicates general information for debugging or tracking (e.g., view registration or state update).
///       - `debug` (4): Indicates detailed debugging information for developers (e.g., intermediate state changes or binding updates).
///       - `verbose` (5): Indicates exhaustive diagnostic information (e.g., every property validation or view construction step).
///   - Description: Sets a custom logger function to handle debugging and error reporting. The function is stored globally and called from native via evaluateJavaScript.
///   - Example: `ActionUI.setLogger(function(message, level) { console.log("[Level " + level + "] " + message); });`
///
/// - `setElementValue(windowUUID, viewID, viewPartID, value)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `viewPartID`: Number -  part identifier (e.g., for multi-column tables; defaults to 0).
///     - `value`: Any - The value to set, serialized to JSON (e.g., String, Number, Boolean, Object, Array).
///   - Description: Sets the value of a view element by posting a message to native code.
///   - Example: `ActionUI.setElementValue("window-12345", 2, 0, "New text");`
///
/// - `setElementValueFromString(windowUUID, viewID, viewPartID, value, contentType?)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `viewPartID`: Number - Part identifier (e.g., for multi-column tables; pass 0 for default).
///     - `value`: String - The string representation of the value, parsed to the view's expected type (e.g., ISO 8601 for Date).
///     - `contentType`: String or null - Optional content-type hint: `"markdown"`, `"html"`, `"rtf"`, `"json"`, or null for default.
///   - Description: Sets the value of a view element from a string by posting a message to native code.
///   - Example: `ActionUI.setElementValueFromString("window-12345", 2, 0, "2023-10-05T12:00:00Z");`
///
/// - `getElementValue(windowUUID, viewID, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Returns: Promise<Any> - The value as a JavaScript-compatible type (e.g., String, Number, Object, Array), or undefined if not found.
///   - Description: Retrieves the value of a view element asynchronously via a native bridge.
///   - Example: `ActionUI.getElementValue("window-12345", 2, 0).then(value => console.log(value));`
///
/// - `getElementValueAsString(windowUUID, viewID, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Returns: Promise<String> - The string representation of the view element's value (e.g., ISO 8601 for Date), or undefined if not found.
///   - Description: Retrieves the string representation of the view element's value asynchronously.
///   - Example: `ActionUI.getElementValueAsString("window-12345", 2, 0).then(stringValue => console.log(stringValue));`
///
/// - `registerActionHandler(actionID, handlerFunction)`
///   - Parameters:
///     - `actionID`: String - Identifier for the action (e.g., "button.click").
///     - `handlerFunction`: Function - A function to execute when the action is triggered, receiving `actionID` (String), `windowUUID` (String), `viewID` (Number), `viewPartID` (Number), and `context` (Any, null if absent).
///   - Description: Registers a handler for a specific action ID, stored globally in JavaScript and called from native code via evaluateJavaScript.
///   - Example: `ActionUI.registerActionHandler("button.click", function(actionID, windowUUID, viewID, viewPartID, context) { console.log("Action: " + actionID); });`
///
/// - `unregisterActionHandler(actionID)`
///   - Parameters:
///     - `actionID`: String - Identifier for the action (e.g., "button.click").
///   - Description: Unregisters a handler for a specific action ID, removing it from the global map.
///   - Example: `ActionUI.unregisterActionHandler("button.click");`
///
/// - `setDefaultActionHandler(handlerFunction)`
///   - Parameters:
///     - `handlerFunction`: Function - A function for unmatched actions, receiving `actionID` (String), `windowUUID` (String), `viewID` (Number), `viewPartID` (Number), and `context` (Any, null if absent).
///   - Description: Sets a default handler for unregistered action IDs, stored globally and called from native code.
///   - Example: `ActionUI.setDefaultActionHandler(function(actionID, windowUUID, viewID, viewPartID, context) { console.log("Default: " + actionID); });`
///
/// - `removeDefaultActionHandler()`
///   - Parameters: None
///   - Description: Removes the default action handler.
///   - Example: `ActionUI.removeDefaultActionHandler();`
///
/// - `getElementColumnCount(windowUUID, viewID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///   - Returns: Promise<Number> - The number of data columns, or 0 if the view is not a table or not found.
///   - Description: Returns the number of data columns for a table/list view, including hidden columns beyond the visible ones.
///   - Example: `ActionUI.getElementColumnCount("window-12345", 1).then(count => console.log(count));`
///
/// - `getElementRows(windowUUID, viewID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///   - Returns: Promise<Array<Array<String>>> - Array of string arrays representing rows, or undefined if the view is not a table or not found.
///   - Description: Returns all content rows for a table/list view element.
///   - Example: `ActionUI.getElementRows("window-12345", 1).then(rows => console.log(rows));`
///
/// - `clearElementRows(windowUUID, viewID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///   - Description: Clears all content rows from a table/list view element, preserving column definitions.
///   - Example: `ActionUI.clearElementRows("window-12345", 1);`
///
/// - `setElementRows(windowUUID, viewID, rows)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `rows`: Array<Array<String>> - Rows to set as the new content, serialized to JSON.
///   - Description: Replaces all content rows for a table/list view element. Clears the current selection if the selected row is no longer present.
///   - Example: `ActionUI.setElementRows("window-12345", 1, [["Alice", "30"], ["Bob", "25"]]);`
///
/// - `appendElementRows(windowUUID, viewID, rows)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `rows`: Array<Array<String>> - Rows to append, serialized to JSON.
///   - Description: Appends rows to a table/list view element's existing content.
///   - Example: `ActionUI.appendElementRows("window-12345", 1, [["Charlie", "22"]]);`
///
/// - `getElementProperty(windowUUID, viewID, propertyName)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `propertyName`: String - The property key (e.g., "columns", "widths", "disabled").
///   - Returns: Promise<Any> - The property value, or undefined if not found.
///   - Description: Gets a structural property value for a view element by property name.
///   - Example: `ActionUI.getElementProperty("window-12345", 1, "disabled").then(val => console.log(val));`
///
/// - `setElementProperty(windowUUID, viewID, propertyName, value)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `propertyName`: String - The property key (e.g., "columns", "widths", "disabled").
///     - `value`: Any - The new property value, serialized to JSON.
///   - Description: Sets a structural property value for a view element by property name.
///   - Example: `ActionUI.setElementProperty("window-12345", 1, "disabled", true);`
///
/// - `presentModal(windowUUID, jsonString, format, style, onDismissActionID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `jsonString`: String - JSON or plist string describing the modal's view hierarchy.
///     - `format`: String - `"json"` or `"plist"`.
///     - `style`: String - `"sheet"` or `"fullScreenCover"`.
///     - `onDismissActionID`: String or null - actionID fired when the modal is dismissed.
///   - Description: Presents a window-level modal sheet or full-screen cover from a JSON/plist string. Fire-and-forget; no return value.
///   - Example: `ActionUI.presentModal("win-123", jsonStr, "json", "sheet", "settings.closed");`
///
/// - `dismissModal(windowUUID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///   - Description: Dismisses the active window-level modal and fires onDismissActionID if set.
///   - Example: `ActionUI.dismissModal("win-123");`
///
/// - `presentAlert(windowUUID, title, message, buttons)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `title`: String - Alert title.
///     - `message`: String or null - Optional alert message.
///     - `buttons`: Array or null - Optional array of button descriptors `[{title, role?, actionID?}]`; null defaults to single OK button.
///   - Description: Presents a window-level alert dialog. Fire-and-forget.
///   - Example: `ActionUI.presentAlert("win-123", "Delete?", null, [{title:"Delete",role:"destructive",actionID:"del"},{title:"Cancel",role:"cancel"}]);`
///
/// - `presentConfirmationDialog(windowUUID, title, message, buttons)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `title`: String - Dialog title.
///     - `message`: String or null - Optional dialog message.
///     - `buttons`: Array - Array of button descriptors `[{title, role?, actionID?}]`.
///   - Description: Presents a window-level confirmation dialog (action sheet style on iOS). Fire-and-forget.
///   - Example: `ActionUI.presentConfirmationDialog("win-123", "Save?", null, [{title:"Save",actionID:"save"},{title:"Cancel",role:"cancel"}]);`
///
/// - `dismissDialog(windowUUID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///   - Description: Dismisses the active window-level alert or confirmation dialog. SwiftUI dismisses automatically on button tap.
///   - Example: `ActionUI.dismissDialog("win-123");`
///
/// Design decision: APIs are asynchronous where returns are involved (e.g., getElementValue) due to the WebKit bridge's nature. Complex types (e.g., value in setElementValue) are serialized to JSON. Action handlers and logger are stored as global JavaScript functions and called from native code via evaluateJavaScript. The adapter uses a hidden WKWebView (offscreen) to execute JavaScript, enabling remote script loading while maintaining a native ActionUI experience.
/// App Store compliance: WKWebView allows loading remote JavaScript as web content, which is permitted under App Store guidelines (Guideline 4.7) as long as the app provides substantial native functionality. Scripts can be bundled or fetched non-executably; avoid arbitrary code execution (e.g., eval of user input).

/// Message handler name for JavaScript-to-native communication.
private let messageHandlerName = "actionUI"

/// Logger bridge to forward native logs to JavaScript.
private class WebKitJSLoggerBridge: ActionUILogger {
    weak var adapter: ActionUIWebKitJS?
    
    init(adapter: ActionUIWebKitJS) {
        self.adapter = adapter
    }
    
    func log(_ message: String, _ level: LoggerLevel) {
        guard let adapter = adapter else {
            print("Logger adapter is nil: \(message) [Level \(level.rawValue)]")
            return
        }
        let js = """
        if (typeof window.actionUI_logger === 'function') {
            window.actionUI_logger("\(message.jsonEscaped)", \(level.rawValue));
            null;
        } else {
            console.log("ActionUI logger not initialized: \(message.jsonEscaped) [Level \(level.rawValue)]");
            null;
        }
        """
        adapter.webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("Logger call error: \(error)")
            } else {
                print("Logger call result: \(result ?? "nil")")
            }
        }
    }
}

/// Public entry point for the ActionUI WebKit JavaScript adapter, using a WKWebView to run JavaScript and bridge to the ActionUI library.
/// Design decision: Uses a hidden WKWebView (offscreen) for headless JavaScript execution, communicating via postMessage (JS to native) and evaluateJavaScript (native to JS). APIs mirror ActionUIJavaScript but are async for gets and use JSON for complex types. Action handlers and logger are forwarded to JavaScript globals.
/// App Store compliance: WKWebView supports remote JavaScript as web content; scripts must be bundled or fetched non-executably.
@MainActor
public class ActionUIWebKitJS: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    public let webView: WKWebView
    
    /// Static reference to the shared ActionUIModel singleton.
    /// Design decision: Static to ensure all instances interact with the same model, aligning with ActionUIModel.shared singleton and other adapters (ActionUISwift, ActionUIObjC, ActionUIJavaScript).
    private static let model = ActionUIModel.shared
    
    /// Enum for JavaScript source, matching ViewController.swift.
    public enum JavaScriptSource {
        case appBundle(fileName: String)
        case localFilePath(path: String)
        case remoteURL(url: String)
    }
    
    public init(jsSource: JavaScriptSource) {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.setValue(true, forKey: "developerExtrasEnabled") // Enable Web Inspector
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isHidden = true
        
        super.init()
        
        config.userContentController.add(self, name: messageHandlerName)
        config.userContentController.add(self, name: "consoleLog")
        webView.navigationDelegate = self
        
        // Modified: Inject ActionUIWebKitJSBridge.js at document start
        if let bridgeURL = Bundle.main.url(forResource: "ActionUIWebKitJSBridge", withExtension: "js"),
           let bridgeSource = try? String(contentsOf: bridgeURL, encoding: .utf8) {
            let userScript = WKUserScript(source: bridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(userScript)
            print("Injected ActionUIWebKitJSBridge.js at document start")
        } else {
            print("Failed to load ActionUIWebKitJSBridge.js from bundle")
        }
        
        setupNativeHandlers()
        loadJavaScript(from: jsSource)
    }
    
    // Load JavaScript from source and prepare HTML
    private func loadJavaScript(from source: JavaScriptSource) {
        var scriptURL: URL?
        
        switch source {
        case .appBundle(let fileName):
            scriptURL = Bundle.main.url(forResource: fileName, withExtension: "js")
        case .localFilePath(let path):
            scriptURL = URL(fileURLWithPath: path)
        case .remoteURL(let urlString):
            scriptURL = URL(string: urlString)
        }
        
        guard let scriptURL = scriptURL else {
            print("Invalid JavaScript source URL: \(source)")
            return
        }
        
        print("Attempting to load JavaScript from: \(scriptURL.absoluteString)")
        if FileManager.default.fileExists(atPath: scriptURL.path) {
            print("Confirmed: BusinessLogic.js exists at \(scriptURL.path)")
        } else {
            print("Error: BusinessLogic.js not found at \(scriptURL.path)")
        }
        
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            print("Invalid HTML file URL for index.html")
            return
        }
        
        print("Loading HTML from: \(htmlURL.absoluteString)")
        if FileManager.default.fileExists(atPath: htmlURL.path) {
            print("Confirmed: index.html exists at \(htmlURL.path)")
        } else {
            print("Error: index.html not found at \(htmlURL.path)")
        }
        
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }
    // Set up native-side handlers
    
    private func setupNativeHandlers() {
        ActionUIWebKitJS.model.logger = WebKitJSLoggerBridge(adapter: self)
        
        ActionUIWebKitJS.model.setDefaultActionHandler { [weak self] actionID, windowUUID, viewID, viewPartID, context in
            guard let self = self else { return }
            let argsJSON = self.jsonForActionHandlerArgs(actionID, windowUUID, viewID, viewPartID, context)
            print("Dispatching action: \(actionID) with args: \(argsJSON)")
            let js = "window.actionUIDispatch('action', \(actionID.jsonString), \(argsJSON))"
            self.webView.evaluateJavaScript(js) { result, error in
                if let error = error {
                    print("Action handler call error: \(error)")
                } else {
                    print("Action handler call result: \(result ?? "nil")")
                }
            }
        }
    }
    // Convert action args to JSON string
    
    private func jsonForActionHandlerArgs(_ actionID: String, _ windowUUID: String, _ viewID: Int, _ viewPartID: Int, _ context: Any?) -> String {
        // Modified: Add explicit type annotation to fix compilation error
        var dict: [String: Any] = [
            "actionID": actionID,
            "windowUUID": windowUUID,
            "viewID": viewID,
            "viewPartID": viewPartID
        ]
        // Modified: Safely handle context serialization for String, Number, and containers
        if let context = context {
            if let stringValue = context as? String {
                // Handle String by setting directly (will be serialized as JSON string)
                dict["context"] = stringValue
            } else if let numberValue = context as? NSNumber {
                // Handle Number (Int, Double, etc.) via NSNumber
                dict["context"] = numberValue
            } else if JSONSerialization.isValidJSONObject(context) {
                // Handle Array or Dictionary
                dict["context"] = context
            } else {
                // Non-serializable types fall back to null
                print("Non-serializable context, using null: \(type(of: context))")
                dict["context"] = NSNull()
            }
        } else {
            dict["context"] = NSNull()
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            print("JSON serialization error: \(error)")
            return "{}"
        }
    }
    // Helper to coerce JSON numbers to Int
    
    private func numberAsInt(_ value: Any) -> Int? {
        switch value {
        case let doubleValue as Double:
            if doubleValue.isFinite && doubleValue == floor(doubleValue) {
                return Int(doubleValue)
            } else {
                print("Invalid double value")
                return nil
            }
        case let intValue as Int:
            return intValue
        case let numberValue as NSNumber:
            let doubleValue = numberValue.doubleValue
            if doubleValue.isFinite && doubleValue == floor(doubleValue) {
                return Int(doubleValue)
            } else {
                print("Invalid double value")
                return nil
            }
        default:
            print("Invalid numeric type. Expected number, got \(type(of: value))")
            return nil
        }
    }
    
    // Parse an array of button descriptors from a JS-passed array ([Any]) into [ActionUI.DialogButton].
    // Expected element shape: {"title": String, "role"?: String, "actionID"?: String}
    private func parseDialogButtons(_ array: [Any]?) -> [ActionUI.DialogButton]? {
        guard let array = array, !array.isEmpty else { return nil }
        return array.compactMap { element -> ActionUI.DialogButton? in
            guard let dict = element as? [String: Any],
                  let title = dict["title"] as? String else { return nil }
            let role: SwiftUI.ButtonRole? = switch dict["role"] as? String {
                case "cancel": .cancel
                case "destructive": .destructive
                default: nil
            }
            return ActionUI.DialogButton(title: title, role: role, actionID: dict["actionID"] as? String)
        }
    }

    // Handle messages from JavaScript
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "consoleLog", let body = message.body as? [String: Any], let msg = body["message"] as? String {
            print("JS Console: \(msg)")
            return
        }
        
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let args = body["args"] as? [Any] else {
            print("Invalid message format from JavaScript")
            return
        }
        
        let methodLog = "Received message for method: \(method)"
        print(methodLog)
        
        switch method {
        case "testFromJS":
            print("Received test from JS: Native side called successfully!")
        case "setElementValue":
            if args.count == 4, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let viewPartID = numberAsInt(args[2]) {
                let value = args[3]
                print("setElementValue called with windowUUID: \(windowUUID), viewID: \(viewID), viewPartID: \(viewPartID), value: \(value)")
                ActionUIWebKitJS.model.setElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: value)
            } else {
                print("Invalid arguments for setElementValue: \(args)")
            }
        case "setElementValueFromString":
            // args: [windowUUID, viewID, viewPartID, value, contentType?]
            if args.count >= 4, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let viewPartID = numberAsInt(args[2]),
               let value = args[3] as? String {
                let contentType = args.count >= 5 ? args[4] as? String : nil
                ActionUIWebKitJS.model.setElementValueFromString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: value, contentType: contentType)
            } else {
                print("Invalid arguments for setElementValueFromString: \(args)")
            }
        case "getElementValue":
            if args.count == 3, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let viewPartID = numberAsInt(args[2]) {
                let value = ActionUIWebKitJS.model.getElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID)
                // Modified: Handle String and JSON-serializable types
                let json: String
                print("getElementValue returned value of type: \(type(of: value))")
                if let stringValue = value as? String {
                    // For String, escape it as a JSON string
                    json = "\"\(stringValue.jsonEscaped)\""
                } else if let value = value, JSONSerialization.isValidJSONObject(value) {
                    // For JSON-serializable types (e.g., Array, Dictionary)
                    json = (try? JSONSerialization.string(with: value)) ?? "null"
                } else {
                    // For nil or non-serializable types
                    json = "null"
                }
                let id = body["id"] as? String ?? ""
                webView.evaluateJavaScript("window.postMessage({id: '\(id.jsonEscaped)', result: \(json)})") { _, error in
                    if let error = error {
                        print("getElementValue response error: \(error)")
                    } else {
                        print("getElementValue response sent: \(json)")
                    }
                }
            } else {
                print("Invalid arguments for getElementValue: \(args)")
            }
        case "getElementColumnCount":
            if args.count == 2, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]) {
                let columnCount = ActionUIWebKitJS.model.getElementColumnCount(windowUUID: windowUUID, viewID: viewID)
                let id = body["id"] as? String ?? ""
                webView.evaluateJavaScript("window.postMessage({id: '\(id.jsonEscaped)', result: \(columnCount)})") { _, error in
                    if let error = error {
                        print("getElementColumnCount response error: \(error)")
                    }
                }
            } else {
                print("Invalid arguments for getElementColumnCount: \(args)")
            }
        case "getElementRows":
            if args.count == 2, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]) {
                let rows = ActionUIWebKitJS.model.getElementRows(windowUUID: windowUUID, viewID: viewID)
                let id = body["id"] as? String ?? ""
                let json: String
                if let rows = rows, let data = try? JSONSerialization.data(withJSONObject: rows), let str = String(data: data, encoding: .utf8) {
                    json = str
                } else {
                    json = "null"
                }
                webView.evaluateJavaScript("window.postMessage({id: '\(id.jsonEscaped)', result: \(json)})") { _, error in
                    if let error = error {
                        print("getElementRows response error: \(error)")
                    }
                }
            } else {
                print("Invalid arguments for getElementRows: \(args)")
            }
        case "clearElementRows":
            if args.count == 2, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]) {
                ActionUIWebKitJS.model.clearElementRows(windowUUID: windowUUID, viewID: viewID)
            } else {
                print("Invalid arguments for clearElementRows: \(args)")
            }
        case "setElementRows":
            if args.count == 3, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let rows = args[2] as? [[String]] {
                ActionUIWebKitJS.model.setElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
            } else {
                print("Invalid arguments for setElementRows: \(args)")
            }
        case "appendElementRows":
            if args.count == 3, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let rows = args[2] as? [[String]] {
                ActionUIWebKitJS.model.appendElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
            } else {
                print("Invalid arguments for appendElementRows: \(args)")
            }
        case "getElementProperty":
            if args.count == 3, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let propertyName = args[2] as? String {
                let value = ActionUIWebKitJS.model.getElementProperty(windowUUID: windowUUID, viewID: viewID, propertyName: propertyName)
                let id = body["id"] as? String ?? ""
                let json: String
                if let value = value, JSONSerialization.isValidJSONObject(value) {
                    json = (try? JSONSerialization.string(with: value)) ?? "null"
                } else if let stringValue = value as? String {
                    json = "\"\(stringValue.jsonEscaped)\""
                } else if let numberValue = value as? NSNumber {
                    json = numberValue.stringValue
                } else if let boolValue = value as? Bool {
                    json = boolValue ? "true" : "false"
                } else {
                    json = "null"
                }
                webView.evaluateJavaScript("window.postMessage({id: '\(id.jsonEscaped)', result: \(json)})") { _, error in
                    if let error = error {
                        print("getElementProperty response error: \(error)")
                    }
                }
            } else {
                print("Invalid arguments for getElementProperty: \(args)")
            }
        case "setElementProperty":
            if args.count == 4, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]),
               let propertyName = args[2] as? String {
                let value = args[3]
                ActionUIWebKitJS.model.setElementProperty(windowUUID: windowUUID, viewID: viewID, propertyName: propertyName, value: value)
            } else {
                print("Invalid arguments for setElementProperty: \(args)")
            }
        case "getElementInfo":
            if args.count == 1, let windowUUID = args[0] as? String {
                let info = ActionUIWebKitJS.model.getElementInfo(windowUUID: windowUUID)
                // Convert [Int: String] to [String: String] for JSON serialization
                let stringKeyedInfo = Dictionary(uniqueKeysWithValues: info.map { (String($0.key), $0.value) })
                let json = (try? JSONSerialization.string(with: stringKeyedInfo)) ?? "{}"
                let id = body["id"] as? String ?? ""
                webView.evaluateJavaScript("window.postMessage({id: '\(id.jsonEscaped)', result: \(json)})") { _, error in
                    if let error = error {
                        print("getElementInfo response error: \(error)")
                    }
                }
            } else {
                print("Invalid arguments for getElementInfo: \(args)")
            }
        case "getElementValueAsString":
            // args: [windowUUID, viewID, viewPartID?, contentType?]
            if args.count >= 2, let windowUUID = args[0] as? String,
               let viewID = numberAsInt(args[1]) {
                let viewPartID = args.count >= 3 ? numberAsInt(args[2]) ?? 0 : 0
                let contentType = args.count >= 4 ? args[3] as? String : nil
                let value = ActionUIWebKitJS.model.getElementValueAsString(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, contentType: contentType) ?? ""
                let escaped = value.jsonEscaped
                let id = body["id"] as? String ?? ""
                webView.evaluateJavaScript("window.postMessage({id: '\(id.jsonEscaped)', result: '\(escaped)'})") { _, error in
                    if let error = error {
                        print("getElementValueAsString response error: \(error)")
                    }
                }
            } else {
                print("Invalid arguments for getElementValueAsString: \(args)")
            }
        case "presentModal":
            // args: [windowUUID, jsonString, format, style, onDismissActionID?]
            if args.count >= 4,
               let windowUUID   = args[0] as? String,
               let jsonString   = args[1] as? String,
               let format       = args[2] as? String,
               let styleString  = args[3] as? String,
               let data         = jsonString.data(using: .utf8) {
                let style: ActionUI.ModalStyle = styleString == "fullScreenCover" ? .fullScreenCover : .sheet
                let dismissID = args.count >= 5 ? args[4] as? String : nil
                do {
                    try ActionUIWebKitJS.model.presentModal(windowUUID: windowUUID, data: data, format: format, style: style, onDismissActionID: dismissID)
                } catch {
                    print("presentModal error: \(error)")
                }
            } else {
                print("Invalid arguments for presentModal: \(args)")
            }
        case "dismissModal":
            if args.count >= 1, let windowUUID = args[0] as? String {
                ActionUIWebKitJS.model.dismissModal(windowUUID: windowUUID)
            } else {
                print("Invalid arguments for dismissModal: \(args)")
            }
        case "presentAlert":
            // args: [windowUUID, title, message?, buttons?]
            if args.count >= 2, let windowUUID = args[0] as? String, let title = args[1] as? String {
                let message  = args.count >= 3 ? args[2] as? String : nil
                let buttons  = args.count >= 4 ? parseDialogButtons(args[3] as? [Any]) : nil
                if let buttons {
                    ActionUIWebKitJS.model.presentAlert(windowUUID: windowUUID, title: title, message: message, buttons: buttons)
                } else {
                    ActionUIWebKitJS.model.presentAlert(windowUUID: windowUUID, title: title, message: message)
                }
            } else {
                print("Invalid arguments for presentAlert: \(args)")
            }
        case "presentConfirmationDialog":
            // args: [windowUUID, title, message?, buttons]
            if args.count >= 2, let windowUUID = args[0] as? String, let title = args[1] as? String {
                let message  = args.count >= 3 ? args[2] as? String : nil
                let buttons  = args.count >= 4 ? parseDialogButtons(args[3] as? [Any]) ?? [] : []
                ActionUIWebKitJS.model.presentConfirmationDialog(windowUUID: windowUUID, title: title, message: message, buttons: buttons)
            } else {
                print("Invalid arguments for presentConfirmationDialog: \(args)")
            }
        case "dismissDialog":
            if args.count >= 1, let windowUUID = args[0] as? String {
                ActionUIWebKitJS.model.dismissDialog(windowUUID: windowUUID)
            } else {
                print("Invalid arguments for dismissDialog: \(args)")
            }
        default:
            print("Unknown method: \(method)")
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("WebView navigation finished")
        testNativeToJS()
        // Modified: Removed runBusinessLogic trigger as BusinessLogic.js runs immediately
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("WebView navigation failed: \(error)")
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("WebView provisional navigation failed: \(error)")
    }
    
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("WebView didCommit navigation")
    }
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("WebView didStartProvisionalNavigation")
    }
    
    public func testNativeToJS() {
        webView.evaluateJavaScript("window.testFromNative()") { result, error in
            if let error = error {
                print("Test native to JS error: \(error)")
            } else {
                print("Test native to JS result: \(result ?? "nil")")
            }
        }
    }
    
    // MARK: - Swift-side Loading Methods (mirroring ActionUISwift)
    
    /// Loads a SwiftUI view from a JSON or plist description at the given URL (local or remote).
    /// Design decision: Provided for Swift host code to load views after JavaScript has potentially interacted with the model (e.g., set values or handlers).
    public func loadView(from url: URL, windowUUID: String, isContentView: Bool) -> any SwiftUI.View {
        let logger = ActionUIWebKitJS.model.logger
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

// Helper for JSON string conversion
extension JSONSerialization {
    static func string(with obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// Helper for escaping strings for JavaScript
extension String {
    var jsonEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    var jsonString: String {
        do {
            let data = try JSONSerialization.data(withJSONObject: [self], options: [])
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) ?? "\"\""
        } catch {
            return "\"\""
        }
    }
}
