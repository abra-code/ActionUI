/*
 Sample JSON for TabBarItem:
 {
   "type": "TabBarItem",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Home",     // Optional: String for title, defaults to "Item"
     "content": { "type": "Text", "properties": { "text": "Home" } }, // Required: Nested view
     "systemImage": "house" // Optional: String for SF Symbol, defaults to nil
   }
   // Note: These properties are specific to TabBarItem. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TabBarItem: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Item"
        }
        if validatedProperties["content"] == nil {
            print("Warning: TabBarItem requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["systemImage"] == nil {
            validatedProperties["systemImage"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("TabBarItem") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let title = properties["title"] as? String ?? "Item"
            let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let systemImage = properties["systemImage"] as? String
            return AnyView(
                TabView {
                    ViewBuilderRegistry.shared.buildView(from: content, state: state, windowUUID: windowUUID)
                        .tabItem {
                            if let image = systemImage {
                                Label(title, systemImage: image)
                            } else {
                                Text(title)
                            }
                        }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("systemImage") { view, properties in
            guard let systemImage = properties["systemImage"] as? String else { return view }
            return AnyView(view.tabItem {
                if let existingView = view as? some View {
                    Label((properties["title"] as? String) ?? "Item", systemImage: systemImage)
                } else {
                    Label((properties["title"] as? String) ?? "Item", systemImage: systemImage)
                }
            })
        }
    }
}