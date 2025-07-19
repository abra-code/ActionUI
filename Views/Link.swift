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

struct Link: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        guard let url = validatedProperties["url"] as? URL else {
            print("Warning: Link requires a valid URL")
            return AnyView(SwiftUI.EmptyView())
        }
        let title = validatedProperties["title"] as? String ?? "Link"
        
        return AnyView(
            SwiftUI.Link(destination: url) {
                Text(title)
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let title = properties["title"] as? String {
            modifiedView = AnyView(modifiedView.overlay(Text(title), alignment: .center))
        }
        return modifiedView
    }
}
