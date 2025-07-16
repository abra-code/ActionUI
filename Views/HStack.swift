/*
 Sample JSON for HStack:
 {
   "type": "HStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0      // Optional: CGFloat for spacing between elements
   },
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: The spacing property is specific to HStack. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct HStack: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let spacing = validatedProperties["spacing"] as? CGFloat {
            validatedProperties["spacing"] = spacing
        } else if validatedProperties["spacing"] != nil {
            print("Warning: HStack spacing must be a CGFloat; ignoring")
            validatedProperties["spacing"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("HStack") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            let spacing = validatedProperties["spacing"] as? CGFloat ?? 0.0
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.HStack(spacing: spacing) {
                    ForEach(children.indices, id: \.self) { index in
                        ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers() {
        // No specific modifiers beyond base View properties
    }
}
