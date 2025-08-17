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
   // Note: These properties are specific to Link. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Link: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        if let title = validatedProperties["title"], !(title is String) {
            logger.log("Invalid type for Link title: expected String, got \(type(of: title)), ignoring", .warning)
            validatedProperties["title"] = nil
        }
        
        if let urlString = validatedProperties["url"] as? String {
            if URL(string: urlString) == nil {
                logger.log("Invalid Link url '\(urlString)', ignoring", .warning)
                validatedProperties["url"] = nil
            }
        } else if validatedProperties["url"] != nil {
            logger.log("Invalid type for Link url: expected String, got \(type(of: properties["url"]!)), ignoring", .warning)
            validatedProperties["url"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        guard let url = properties["url"] as? URL else {
            logger.log("Link missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let title = properties["title"] as? String ?? "Link"
        
        return SwiftUI.Link(destination: url) {
            SwiftUI.Text(title)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        if let title = properties["title"] as? String {
            return view.overlay(SwiftUI.Text(title), alignment: .center)
        }
        return view
    }
}
