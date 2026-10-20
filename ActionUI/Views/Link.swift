// Sources/Views/Link.swift
/*
 Sample JSON for Link:
 {
   "type": "Link",
   "id": 1,
   "properties": {
     "title": "Visit Site", // Optional: String for title, defaults to "Link" in buildView
     "url": "https://example.com" // Optional: URL string, returns EmptyView if nil or invalid
   }
   // Note: These properties are specific to Link. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

extension Link {
    /// Link's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = "Link"
        /// The destination as given; the renderer turns it into a URL.
        var url: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? "Link"
            url = properties["url"] as? String
        }
    }
}

struct Link: ActionUIViewConstruction {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Void.self
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title
        if validatedProperties["title"] != nil && !(validatedProperties["title"] is String) {
            logger.log("Invalid type for Link title: expected String, got \(type(of: validatedProperties["title"]!)), ignoring", .warning)
            validatedProperties["title"] = nil
        }
        
        // Validate url
        if validatedProperties["url"] != nil && !(validatedProperties["url"] is String) {
            logger.log("Invalid type for Link url: expected String, got \(type(of: validatedProperties["url"]!)), ignoring", .warning)
            validatedProperties["url"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        guard let urlString = props.url, let url = URL(string: urlString) else {
            logger.log("Link missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let title = props.title
        
        return SwiftUI.Link(destination: url) {
            SwiftUI.Text(title)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
