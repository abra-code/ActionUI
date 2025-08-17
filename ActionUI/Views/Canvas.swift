/*
 Sample JSON for Canvas:
 {
   "type": "Canvas",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     // drawing instructions could be a whole other spec world. fillCircle is a placeholder for proof of concept
     "render": "fillCircle", // Optional: String identifier for render action, defaults to nil
     "color": "#FF0000"     // Optional: Color for drawing, defaults to black
   }
   // Note: These properties are specific to Canvas. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Canvas: ActionUIViewConstruction {
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
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
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let color = (properties["color"] as? Color) ?? Color.black
        let render = (properties["render"] as? String) ?? "none"
        
        return SwiftUI.Canvas { context, size in
            // example drawing for a proof of concept
            if render == "fillCircle" {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                context.fill(Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            }
        }
    }
}
