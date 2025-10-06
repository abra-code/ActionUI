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
///     - `loggerFunction`: Function - A function that receives a message (string) and level (number, corresponding to `ActionUILogger.Level` raw values: 1=error, 2=warning, 3=info, 4=debug, 5=verbose).
///       - `error` (1): Indicates a critical issue that may prevent normal operation (e.g., invalid JSON causing view rendering failure).
///       - `warning` (2): Indicates a non-critical issue that may affect functionality (e.g., missing optional property with a fallback).
///       - `info` (3): Indicates general information for debugging or tracking (e.g., view registration or state update).
///       - `debug` (4): Indicates detailed debugging information for developers (e.g., intermediate state changes or binding updates).
///       - `verbose` (5): Indicates exhaustive diagnostic information (e.g., every property validation or view construction step).
///   - Description: Sets a custom logger function to handle debugging and error reporting. The function is stored globally and called from native via evaluateJavaScript.
///   - Example: `ActionUI.setLogger(function(message, level) { console.log("[Level " + level + "] " + message); });`
///
/// - `setElementValue(windowUUID, viewID, value, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `value`: Any - The value to set, serialized to JSON (e.g., String, Number, Boolean, Object, Array).
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Description: Sets the value of a view element by posting a message to native code.
///   - Example: `ActionUI.setElementValue("window-12345", 2, "New text", 0);`
///
/// - `setElementValueFromString(windowUUID, viewID, value, viewPartID)`
///   - Parameters:
///     - `windowUUID`: String - Unique identifier for the window.
///     - `viewID`: Number - Unique identifier for the view element.
///     - `value`: String - The string representation of the value, parsed to the view's expected type (e.g., ISO 8601 for Date).
///     - `viewPartID`: Number - Optional part identifier (e.g., for multi-column tables; defaults to 0).
///   - Description: Sets the value of a view element from a string by posting a message to native code.
///   - Example: `ActionUI.setElementValueFromString("window-12345", 2, "2023-10-05T12:00:00Z", 0);`
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
///   - Description: Retrieves the string representation of a view element's value asynchronously.
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
    
    func log(_ message: String, _ level: Level) {
        guard let adapter = adapter else { return }
        let js = "window.actionUI_logger(\(message.jsonEscaped), \(level.rawValue))"
        adapter.webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("Logger call error: \(error)")
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
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.isHidden = true // Offscreen for headless execution
        
        super.init()
        
        // Add self as message handler after super.init
        config.userContentController.add(self, name: messageHandlerName)
        
        webView.navigationDelegate = self // For injecting bridge after load
        loadJavaScript(from: jsSource)
        setupNativeHandlers()
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
        
        guard let url = scriptURL else {
            ActionUIWebKitJS.model.logger.log("Invalid JavaScript source URL", .error)
            return
        }
        
        // Minimal HTML with script reference
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <script src="\(url.absoluteString)"></script>
        </head>
        <body></body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
    
    // Inject ActionUI bridge into JavaScript context
    private func injectActionUI() {
        let bridgeJS = """
        window.actionUI_handlers = {};
        window.actionUI_defaultHandler = null;
        window.actionUI_logger = function() {};
        
        window.ActionUI = {
            setLogger: function(handler) {
                window.actionUI_logger = handler;
            },
            setElementValue: function(windowUUID, viewID, value, viewPartID) {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                    method: 'setElementValue',
                    args: [windowUUID, viewID, value, viewPartID]
                });
            },
            setElementValueFromString: function(windowUUID, viewID, value, viewPartID) {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                    method: 'setElementValueFromString',
                    args: [windowUUID, viewID, value, viewPartID]
                });
            },
            getElementValue: async function(windowUUID, viewID, viewPartID) {
                const id = Math.random().toString(36);
                return new Promise(resolve => {
                    const listener = function(e) {
                        if (e.data.id === id) {
                            resolve(e.data.result);
                            window.removeEventListener('message', listener);
                        }
                    };
                    window.addEventListener('message', listener);
                    window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                        method: 'getElementValue',
                        id: id,
                        args: [windowUUID, viewID, viewPartID]
                    });
                });
            },
            getElementValueAsString: async function(windowUUID, viewID, viewPartID) {
                const id = Math.random().toString(36);
                return new Promise(resolve => {
                    const listener = function(e) {
                        if (e.data.id === id) {
                            resolve(e.data.result);
                            window.removeEventListener('message', listener);
                        }
                    };
                    window.addEventListener('message', listener);
                    window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                        method: 'getElementValueAsString',
                        id: id,
                        args: [windowUUID, viewID, viewPartID]
                    });
                });
            },
            registerActionHandler: function(actionID, handler) {
                window.actionUI_handlers[actionID] = handler;
            },
            unregisterActionHandler: function(actionID) {
                delete window.actionUI_handlers[actionID];
            },
            setDefaultActionHandler: function(handler) {
                window.actionUI_defaultHandler = handler;
            },
            removeDefaultActionHandler: function() {
                window.actionUI_defaultHandler = null;
            }
        };
        """
        webView.evaluateJavaScript(bridgeJS) { _, error in
            if let error = error {
                ActionUIWebKitJS.model.logger.log("Failed to inject ActionUI bridge: \(error)", .error)
            }
        }
    }
    
    // Set up native-side handlers for actions and logger
    private func setupNativeHandlers() {
        // Logger: Forward native logs to JS
        ActionUIWebKitJS.model.logger = WebKitJSLoggerBridge(adapter: self)
        
        // Action handlers: Forward all model actions to JS
        ActionUIWebKitJS.model.setDefaultActionHandler { actionID, windowUUID, viewID, viewPartID, context in
            let argsJSON = self.jsonForArgs(actionID, windowUUID, viewID, viewPartID, context)
            let js = """
            if (window.actionUI_handlers['\(actionID.jsonEscaped)']) {
                window.actionUI_handlers['\(actionID.jsonEscaped)'].apply(null, JSON.parse(\(argsJSON.jsonEscaped)));
            } else if (window.actionUI_defaultHandler) {
                window.actionUI_defaultHandler.apply(null, JSON.parse(\(argsJSON.jsonEscaped)));
            }
            """
            self.webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    ActionUIWebKitJS.model.logger.log("Action handler call error: \(error)", .error)
                }
            }
        }
    }
    
    // Convert action args to JSON string
    private func jsonForArgs(_ actionID: String, _ windowUUID: String, _ viewID: Int, _ viewPartID: Int, _ context: Any?) -> String {
        let dict = [
            "actionID": actionID,
            "windowUUID": windowUUID,
            "viewID": viewID,
            "viewPartID": viewPartID,
            "context": context ?? NSNull()
        ]
        return (try? JSONSerialization.string(with: dict)) ?? "[]"
    }
    
    // Handle messages from JavaScript
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let method = body["method"] as? String, let args = body["args"] as? [Any] else {
            ActionUIWebKitJS.model.logger.log("Invalid message format from JavaScript", .warning)
            return
        }
        
        let id = body["id"] as? String // For async responses
        
        switch method {
        case "setElementValue":
            if args.count == 4, let windowUUID = args[0] as? String, let viewID = args[1] as? Double, let viewPartID = args[3] as? Double {
                let value = args[2] // Directly use args[2] as Any
                ActionUIWebKitJS.model.setElementValue(windowUUID: windowUUID, viewID: Int(viewID), value: value, viewPartID: Int(viewPartID))
            } else {
                ActionUIWebKitJS.model.logger.log("Invalid arguments for setElementValue", .warning)
            }
        case "setElementValueFromString":
            if args.count == 4, let windowUUID = args[0] as? String, let viewID = args[1] as? Double, let value = args[2] as? String, let viewPartID = args[3] as? Double {
                ActionUIWebKitJS.model.setElementValueFromString(windowUUID: windowUUID, viewID: Int(viewID), value: value, viewPartID: Int(viewPartID))
            } else {
                ActionUIWebKitJS.model.logger.log("Invalid arguments for setElementValueFromString", .warning)
            }
        case "getElementValue":
            if args.count == 3, let windowUUID = args[0] as? String, let viewID = args[1] as? Double, let viewPartID = args[2] as? Double {
                let value = ActionUIWebKitJS.model.getElementValue(windowUUID: windowUUID, viewID: Int(viewID), viewPartID: Int(viewPartID))
                let json = (try? JSONSerialization.string(with: value ?? NSNull())) ?? "null"
                webView.evaluateJavaScript("window.postMessage({id: '\(id ?? "")', result: \(json)})") { _, error in
                    if let error = error {
                        ActionUIWebKitJS.model.logger.log("getElementValue response error: \(error)", .error)
                    }
                }
            } else {
                ActionUIWebKitJS.model.logger.log("Invalid arguments for getElementValue", .warning)
            }
        case "getElementValueAsString":
            if args.count == 3, let windowUUID = args[0] as? String, let viewID = args[1] as? Double, let viewPartID = args[2] as? Double {
                let value = ActionUIWebKitJS.model.getElementValueAsString(windowUUID: windowUUID, viewID: Int(viewID), viewPartID: Int(viewPartID)) ?? ""
                let escaped = value.jsonEscaped
                webView.evaluateJavaScript("window.postMessage({id: '\(id ?? "")', result: \(escaped)})") { _, error in
                    if let error = error {
                        ActionUIWebKitJS.model.logger.log("getElementValueAsString response error: \(error)", .error)
                    }
                }
            } else {
                ActionUIWebKitJS.model.logger.log("Invalid arguments for getElementValueAsString", .warning)
            }
        default:
            ActionUIWebKitJS.model.logger.log("Unknown method: \(method)", .warning)
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectActionUI()
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
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
