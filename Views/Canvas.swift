/*
 Sample JSON for Canvas:
 {
   "type": "Canvas",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "render": "drawCircle", // Optional: String identifier for render action, defaults to nil
     "color": "#FF0000"     // Optional: Color for drawing, defaults to black
   }
   // Note: These properties are specific to Canvas. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Canvas: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["render"] == nil {
            validatedProperties["render"] = nil
        }
        if let color = validatedProperties["color"] as? String {
            if let resolvedColor = ColorHelper.resolveColor(color) {
                validatedProperties["color"] = resolvedColor
            } else {
                print("Warning: Canvas color '\(color)' invalid; defaulting to black")
                validatedProperties["color"] = Color.black
            }
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Canvas") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let color = (properties["color"] as? Color) ?? Color.black
            return AnyView(
                Canvas { context, size in
                    if properties["render"] as? String == "drawCircle" {
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2
                        context.fill(Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("render") { view, properties in
            guard properties["render"] as? String == "drawCircle" else { return view }
            return view // Render logic handled in register; no additional modifier needed
        }
        registry.register("color") { view, properties in
            guard let color = properties["color"] as? Color else { return view }
            return AnyView(view.overlay(
                Color.clear.frame(width: 0, height: 0), // Placeholder to trigger redraw
                alignment: .center
            ).environment(\.colorScheme, .dark)) // Example environment adjustment
        }
    }
}
