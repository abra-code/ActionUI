/*
 Sample JSON for Link:
 {
   "type": "Link",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Visit Site", // Optional: String for title, defaults to "Link"
     "url": "https://example.com" // Required: URL string
   }
   // Note: These properties are specific to Link. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Link: StaticElement, ViewBuilder {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Link") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            guard let url = properties["url"] as? URL else {
                print("Warning: Link requires a valid URL")
                return AnyView(EmptyView())
            }
            let title = properties["title"] as? String ?? "Link"
            return AnyView(
                Link(destination: url) {
                    Text(title)
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("title") { view, properties in
            guard let title = properties["title"] as? String else { return view }
            return AnyView((view as? some View)?.overlay(Text(title), alignment: .center) ?? Text(title))
        }
    }
}
