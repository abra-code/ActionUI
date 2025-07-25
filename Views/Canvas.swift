/*
 Sample JSON for Canvas:
 {
   "type": "Canvas",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "render": "drawCircle", // Optional: String identifier for render action, defaults to nil
     "color": "#FF0000"     // Optional: Color for drawing, defaults to black
   }
   // Note: These properties are specific to Canvas. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Canvas: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
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
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { _, _, _, _ in
        return AnyView(
            SwiftUI.Canvas { context, size in
                // Render logic moved to applyModifiers
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        let color = (properties["color"] as? Color) ?? Color.black
        if properties["render"] as? String == "drawCircle" {
            modifiedView = AnyView(modifiedView.canvasRenderer { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                context.fill(Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            })
        }
        return modifiedView
    }
}
