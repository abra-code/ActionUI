/*
 Sample JSON for NavigationView:
 {
   "type": "NavigationView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Home" } }, // Required: Nested view
     "navigationTitle": "App" // Optional: String for navigation title, defaults to nil
   }
   // Note: These properties are specific to NavigationView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationView: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["content"] == nil {
            print("Warning: NavigationView requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["navigationTitle"] == nil {
            validatedProperties["navigationTitle"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("NavigationView") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            return AnyView(
                NavigationView {
                    ViewBuilderRegistry.shared.buildView(from: content, state: state, windowUUID: windowUUID)
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("navigationTitle") { view, properties in
            guard let navigationTitle = properties["navigationTitle"] as? String else { return view }
            return AnyView(view.navigationTitle(navigationTitle))
        }
    }
}
