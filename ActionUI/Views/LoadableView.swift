// Sources/Views/LoadableView.swift
/*
 Sample JSON for LoadableView:
 {
   "type": "LoadableView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/view.json", // Optional: String URL to remote JSON or binary plist (http://, https://)
     "filePath": "/path/to/view.json",       // Optional: String absolute path to local JSON or binary plist
     "name": "HelloWorld.json",              // Optional: String name of JSON or binary plist resource in app bundle
     "viewDidLoadActionID": "view.loaded"    // Optional: String action triggered once after a new sub-view is loaded. Not re-triggered on SwiftUI body rebuilds for the same source.
   }
   // Note: Requires exactly one of "url", "filePath", or "name" to be valid. Loads JSON or binary plist, determined by .json or .plist extension, parses into ActionUIElementBase using ActionUIModel.loadDescription, and renders ActionUIView. Remote "url" loads asynchronously with ProgressView; local "filePath" or bundle "name" loads synchronously in init. Assumes unique IDs in loaded description to avoid conflicts with existing windowModels. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Note: Invalid sources or unsupported extensions will result in error display. The source (url/filePath/name) is the designated value (valueType: String.self), settable via ActionUIModel.setElementValue, with heuristics: http:// or https:// for URL, file:// or / for filePath, else bundle name.
 }
*/

import SwiftUI
import Foundation

struct LoadableView: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var valueType: Any.Type = String.self // String for url, filePath, or name
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Lightweight type checks only
        if properties["url"] != nil && !(properties["url"] is String) {
            logger.log("LoadableView url must be a String; ignoring", .warning)
            validatedProperties["url"] = nil
        }
        
        if properties["filePath"] != nil && !(properties["filePath"] is String) {
            logger.log("LoadableView filePath must be a String; ignoring", .warning)
            validatedProperties["filePath"] = nil
        }
        
        if properties["name"] != nil && !(properties["name"] is String) {
            logger.log("LoadableView name must be a String; ignoring", .warning)
            validatedProperties["name"] = nil
        }
        
        // Ensure exactly one source is valid
        let sources = ["url", "filePath", "name"].compactMap { validatedProperties[$0] }
        if sources.isEmpty {
            logger.log("LoadableView requires one of 'url', 'filePath', or 'name'; displaying error", .error)
        } else if sources.count > 1 {
            logger.log("LoadableView has multiple sources; prioritizing 'url' > 'filePath' > 'name'", .warning)
            if validatedProperties["url"] != nil {
                validatedProperties["filePath"] = nil
                validatedProperties["name"] = nil
            } else if validatedProperties["filePath"] != nil {
                validatedProperties["name"] = nil
            }
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in

        let isContentView = false
        let viewDidLoadActionID = properties["viewDidLoadActionID"] as? String
        // Use model.value if set (heuristics to interpret), else fallback to validated properties
        guard let value = Self.initialValue(model) as? String, !value.isEmpty else {
            logger.log("No valid source for LoadableView, displaying error SwiftUI.Text", .warning)
            return SwiftUI.Text("No valid source provided")
        }

        // Heuristics to build the appropriate content view from a string value
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            guard let url = URL(string: value) else {
                logger.log("Invalid URL: \(value)", .warning)
                return SwiftUI.Text("Invalid URL: \(value)")
            }
            logger.log("Interpreting value as remote URL: \(value)", .debug)
            return RemoteLoadableView(url: url, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
        } else {
            var fileURL: URL
            if value.lowercased().hasPrefix("file://") {
                guard let url = URL(string: value), !url.path.isEmpty else {
                    logger.log("Invalid file URL: \(value)", .warning)
                    return SwiftUI.Text("Invalid file URL: \(value)")
                }
                fileURL = url
                logger.log("Interpreting value as file URL: \(value)", .debug)
            } else if value.contains("/") {
                fileURL = URL(fileURLWithPath: value)
                logger.log("Interpreting value as filePath: \(value)", .debug)
            } else {
                let ext = URL(fileURLWithPath: value).pathExtension.lowercased()
                let resourceName = ext.isEmpty ? value : value.replacingOccurrences(of: ".\(ext)", with: "")
                let bundleExt = ext.isEmpty ? "json" : ext
                guard let url = Bundle.main.url(forResource: resourceName, withExtension: bundleExt) ??
                                Bundle.main.url(forResource: resourceName, withExtension: bundleExt == "json" ? "plist" : "json") else {
                    logger.log("Bundle resource '\(value)' not found with .json or .plist", .warning)
                    return SwiftUI.Text("Bundle resource '\(value)' not found")
                }
                fileURL = url
                logger.log("Interpreting value as bundle name: \(value)", .debug)
            }
            return FileLoadableView(fileURL: fileURL, windowUUID: windowUUID, isContentView: isContentView, parentID: element.id, viewDidLoadActionID: viewDidLoadActionID, logger: logger)
        }
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // Fallback to properties (prioritize url > filePath > name)
        if let url = model.validatedProperties["url"] as? String {
            return url
        } else if let filePath = model.validatedProperties["filePath"] as? String {
            return filePath
        } else if let name = model.validatedProperties["name"] as? String {
            return name
        }
        return ""
    }
}
