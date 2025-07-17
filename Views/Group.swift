/*
 Sample JSON for Group:
 {
   "type": "Group",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: Group has no specific properties and does not control layout geometry, relying on the parent container for alignment and spacing. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are supported and applied via ModifierRegistry.shared.applyModifiers to the group as a whole.
 }
*/

import SwiftUI

struct Group: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        return View.validateProperties(properties)
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Group") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            
            let children = element.children ?? []
            
            return AnyView(
                SwiftUI.Group {
                    ForEach(children.indices, id: \.self) { index in
                        ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers beyond base View properties
    }
}
