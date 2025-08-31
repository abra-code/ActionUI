// Sources/Views/ColorPicker.swift
/*
 Sample JSON for ColorPicker:
 {
   "type": "ColorPicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Pick a Color", // Optional: String for title, defaults to "Color" in buildView
     "selectedColor": "#FF0000", // Optional: Initial color (hex or named color), defaults to clear in buildView
     "actionID": "colorpicker.action" // Optional: String for action identifier, triggers on color change
   }
   // Note: These properties are specific to ColorPicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ColorPicker: ActionUIViewConstruction {
    static var valueType: Any.Type { Color.self } // Value is the selected color
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate title (optional, must be String)
        if let title = validatedProperties["title"], !(title is String) {
            logger.log("Invalid type for ColorPicker title: expected String, got \(type(of: title)), ignoring", .warning)
            validatedProperties["title"] = nil
        }
        
        // Validate selectedColor (optional, must be String; defaults applied in buildView)
        if let selectedColor = validatedProperties["selectedColor"], !(selectedColor is String) {
            logger.log("Invalid type for ColorPicker selectedColor: expected String, got \(type(of: selectedColor)), ignoring", .warning)
            validatedProperties["selectedColor"] = nil
        }
        
        // Validate actionID (optional, must be String)
        if let actionID = validatedProperties["actionID"], !(actionID is String) {
            logger.log("Invalid type for ColorPicker actionID: expected String, got \(type(of: actionID)), ignoring", .warning)
            validatedProperties["actionID"] = nil
        }
        
        return validatedProperties
    }
    
    // Builds the ColorPicker view, binding selection to state
    // Design decision: Initializes value as validatedProperties["selectedColor"] or Color.clear if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialColor = ColorHelper.resolveColor((properties["selectedColor"] as? String) ?? "clear") ?? Color.clear
        // Initialize ColorPicker-specific state only if not already set
        // Design decision: Merges value (Color) and validatedProperties conditionally to avoid overwriting existing properties
        if model.value == nil {
            model.value = initialColor
        }
        
        let title = properties["title"] as? String ?? "Color"
        
        let colorBinding = Binding(
            get: { model.value as? Color ?? initialColor },
            set: { newValue in
                model.value = newValue
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return SwiftUI.ColorPicker(title, selection: colorBinding)
    }
}
