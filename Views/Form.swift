/*
 Sample JSON for Form:
 {
   "type": "Form",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "children": [
       { "type": "Text", "properties": { "text": "Field 1" } }
     ] // Required: Array of child views
   }
   // Note: These properties are specific to Form. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Form: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["children"] == nil {
            print("Warning: Form requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Form") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let children = properties["children"] as? [[String: Any]] ?? []
            return AnyView(
                Form {
                    ForEach(children.indices, id: \.self) { index in
                        ViewBuilderRegistry.shared.buildView(from: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers defined for Form at this level; relies on baseline modifiers
    }
}
