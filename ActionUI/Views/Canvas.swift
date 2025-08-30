// Sources/Views/Canvas.swift
/*
 Sample JSON for Canvas:
 {
   "type": "Canvas",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     // drawing instructions could be a whole other spec world. fillCircle is a placeholder for proof of concept
     "render": "fillCircle", // Optional: String identifier for render action, defaults to "none" in buildView
     "color": "#FF0000",    // Optional: Color for drawing (hex or named color), defaults to black in buildView
   }
   // Note: These properties are specific to Canvas. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Canvas: ActionUIViewConstruction {
    static var valueType: Any.Type { Void.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate render (optional, must be String)
        if let render = validatedProperties["render"], !(render is String) {
            logger.log("Invalid type for Canvas render: expected String, got \(type(of: render)), ignoring", .warning)
            validatedProperties["render"] = nil
        }
        
        // Validate color (optional, must be String; defaults applied in buildView)
        if let color = validatedProperties["color"], !(color is String) {
            logger.log("Invalid type for Canvas color: expected String, got \(type(of: color)), ignoring", .warning)
            validatedProperties["color"] = nil
        }
        
        // Validate actionID (optional, must be String)
        if let actionID = validatedProperties["actionID"], !(actionID is String) {
            logger.log("Invalid type for Canvas actionID: expected String, got \(type(of: actionID)), ignoring", .warning)
            validatedProperties["actionID"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let render = properties["render"] as? String ?? "none"
        let color = ColorHelper.resolveColor((properties["color"] as? String) ?? "black") ?? Color.black
        let actionID = properties["actionID"] as? String
        
        return SwiftUI.Canvas { context, size in
            // example drawing for a proof of concept
            if render == "fillCircle" {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2
                context.fill(
                    Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color)
                )
            }
        }.onTapGesture(perform: actionID != nil ? {
            Task { @MainActor in
                ActionUIModel.shared.actionHandler(actionID!, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        } : {})
    }
}
