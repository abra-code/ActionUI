/*
 Sample JSON for Link:
 {
   "type": "Link",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Visit Site", // Optional: String for title, defaults to "Link"
     "url": "https://example.com" // Required: URL string
   }
   // Note: These properties are specific to Link. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Link: ActionUIViewConstruction {
    // Design decision: Defines valueType as Void since Link is a navigational view with no interactive state
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Link"
        }
        if let urlString = validatedProperties["url"] as? String {
            if let url = URL(string: urlString) {
                validatedProperties["url"] = url
            } else {
                print("Warning: Link url '\(urlString)' invalid; defaulting to nil")
                validatedProperties["url"] = nil
            }
        } else {
            print("Warning: Link requires 'url'; defaulting to nil")
            validatedProperties["url"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        guard let url = properties["url"] as? URL else {
            print("Warning: Link requires a valid URL")
            return SwiftUI.EmptyView()
        }
        let title = properties["title"] as? String ?? "Link"
        
        return SwiftUI.Link(destination: url) {
            SwiftUI.Text(title)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        if let title = properties["title"] as? String {
            return view.overlay(SwiftUI.Text(title), alignment: .center)
        }
        return view
    }
}
