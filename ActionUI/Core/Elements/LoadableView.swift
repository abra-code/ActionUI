// Core/Elements/LoadableView.swift
/*
 Sample JSON for LoadableView:
 {
   "type": "LoadableView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/view.json", // Optional: String URL to remote JSON or binary plist (http://, https://)
     "filePath": "/path/to/view.json",       // Optional: String absolute path to local JSON or binary plist
     "name": "HelloWorld.json",              // Optional: String name of JSON or binary plist resource in the app (the host's resource folder, then the app bundle)
     "viewDidLoadActionID": "view.loaded"    // Optional: String action triggered once after a new sub-view is loaded. Not re-triggered on SwiftUI body rebuilds for the same source.
   }
   // Note: Requires exactly one of "url", "filePath", or "name" to be valid. Loads JSON or binary plist, determined by .json or .plist extension, parses into ActionUIElementBase using ActionUIModel.loadDescription, and renders ActionUIView. Remote "url" loads asynchronously with ProgressView; local "filePath" or bundle "name" loads synchronously in init. Assumes unique IDs in loaded description to avoid conflicts with existing windowModels. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Note: Invalid sources or unsupported extensions will result in error display. The source (url/filePath/name) is the designated value (valueType: String.self), settable via ActionUIModel.setElementValue, with heuristics: http:// or https:// for URL, file:// or / for filePath, else bundle name.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension LoadableView {
    /// LoadableView's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The three sources: each a String and nothing else. When several are given, "url" wins over
        /// "filePath" and "filePath" over "name", and the others are nil.
        var url: String?
        var filePath: String?
        var name: String?
        /// Fires once after a new sub-view is loaded.
        var viewDidLoadActionID: String?

        init(_ properties: [String: Any]) {
            url = properties["url"] as? String
            filePath = properties["filePath"] as? String
            name = properties["name"] as? String
            if url != nil {
                filePath = nil
                name = nil
            } else if filePath != nil {
                name = nil
            }
            viewDidLoadActionID = properties["viewDidLoadActionID"] as? String
        }
    }
}

struct LoadableView: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = String.self // String for url, filePath, or name

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        // Fallback to properties (prioritize url > filePath > name)
        let props = Props(model.properties)
        if let url = props.url {
            return url
        } else if let filePath = props.filePath {
            return filePath
        } else if let name = props.name {
            return name
        }
        return ""
    }
}
