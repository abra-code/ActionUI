/*
 Sample JSON for EmptyView:
 {
   "type": "EmptyView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {}
   // Note: EmptyView has no specific properties. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are supported and applied via ModifierRegistry.shared.applyModifiers to the group as a whole.
 }
*/

import SwiftUI

struct EmptyView: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        return View.validateProperties(properties)
    }

    static func register(in registry: ViewBuilderRegistry) {
        registry.register("EmptyView") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            
            return AnyView(SwiftUI.EmptyView())
        }
    }
    
    static func registerModifiers() {
        // No specific modifiers beyond base View properties
    }
}
