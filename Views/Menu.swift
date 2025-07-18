/*
 Sample JSON for Menu:
 {
   "type": "Menu",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Options",  // Optional: String for label, defaults to "Menu"
     "children": [
       { "type": "Button", "properties": { "title": "Option 1" } }
     ] // Required: Array of child views (typically Buttons)
   }
   // Note: These properties are specific to Menu. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Menu: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Menu"
        }
        if validatedProperties["children"] == nil {
            print("Warning: Menu requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Menu") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let label = properties["label"] as? String ?? "Menu"
            let children = properties["children"] as? [[String: Any]] ?? []
            return AnyView(
                Menu(label) {
                    ForEach(children.indices, id: \.self) { index in
                        ViewBuilderRegistry.shared.buildView(from: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("label") { view, properties in
            guard let label = properties["label"] as? String else { return view }
            return AnyView((view as? some View)?.overlay(Text(label), alignment: .center) ?? Text(label))
        }
    }
}
