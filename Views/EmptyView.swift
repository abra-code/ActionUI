/*
 Sample JSON for EmptyView:
 {
   "type": "Group",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   // Note: EmptyView has no specific properties. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius) and additional View protocol modifiers are supported and applied via ModifierRegistry.shared.applyModifiers to the group as a whole.
 }
*/

import SwiftUI

struct EmptyView: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties: [String] = []
        var validatedProperties = properties
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Group; ignoring")
                return false
            }
        }
    }

    static func register(in registry: ViewBuilderRegistry) {
        registry.register("EmptyView") { element, state, windowUUID in
            let validatedProperties = StaticElement.getValidatedProperties(element: element, state: state)
            
            return AnyView(EmptyView())
        }
    }    
}
