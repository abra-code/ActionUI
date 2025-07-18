/*
 Sample JSON for Divider:
 {
   "type": "Divider",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "color": "#FF0000",  // Optional: Color for the divider, defaults to system gray if invalid or nil
     "thickness": 2.0     // Optional: Thickness of the divider, defaults to 1.0
   }
   // Note: These properties are specific to Divider. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Design Decision: Moved color and thickness modifications to registerModifiers() to comply with the guide's directive for centralized modifier management. Invalid color resolution is set to nil, allowing Divider's default color to apply, and nil properties do not trigger modifier application.
 }
*/

import SwiftUI

struct Divider: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if let color = validatedProperties["color"] as? String {
            if let resolvedColor = ColorHelper.resolveColor(color) {
                validatedProperties["color"] = resolvedColor
            } else {
                print("Warning: Divider color '\(color)' invalid; setting to nil to use Divider's default")
                validatedProperties["color"] = nil
            }
        }
        if let thickness = validatedProperties["thickness"] as? Double, thickness > 0 {
            validatedProperties["thickness"] = thickness
        } else if validatedProperties["thickness"] != nil {
            print("Warning: Divider thickness must be a positive number; defaulting to 1.0")
            validatedProperties["thickness"] = 1.0
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Divider") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            return AnyView(
                Divider()
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("color") { view, properties in
            guard let color = properties["color"] as? Color else { return view } // Skip if nil
            return AnyView(view.background(color))
        }
        registry.register("thickness") { view, properties in
            guard let thickness = properties["thickness"] as? Double else { return view } // Skip if nil
            return AnyView(view.frame(height: thickness))
        }
    }
}
