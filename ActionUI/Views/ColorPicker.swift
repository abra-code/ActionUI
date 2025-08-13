/*
 Sample JSON for ColorPicker:
 {
   "type": "ColorPicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Pick a Color", // Optional: String for title, defaults to "Color"
     "selectedColor": "#FF0000" // Optional: Initial color (hex string), defaults to clear
   }
   // Note: These properties are specific to ColorPicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ColorPicker: ActionUIViewConstruction {
    static var valueType: Any.Type { Color.self } // Value is the selected color
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate title
        if validatedProperties["title"] == nil {
            validatedProperties["title"] = "Color"
        }
        
        // Validate selectedColor
        if let selectedColor = validatedProperties["selectedColor"] as? String {
            if let color = ColorHelper.resolveColor(selectedColor) {
                validatedProperties["selectedColor"] = color
            } else {
                print("Warning: ColorPicker selectedColor '\(selectedColor)' invalid; defaulting to clear")
                validatedProperties["selectedColor"] = Color.clear
            }
        }
        
        return validatedProperties
    }
    
    // Builds the ColorPicker view, binding selection to state
    // Design decision: Initializes value as validatedProperties["selectedColor"] or Color.clear if not set, preserving shared state (validatedProperties) from ActionUIRegistry.build
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let initialColor = (properties["selectedColor"] as? Color) ?? Color.clear
        
        // Initialize ColorPicker-specific state only if not already set
        // Design decision: Merges value (Color) and validatedProperties conditionally to avoid overwriting existing properties
        var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["value"] == nil {
            viewSpecificState["value"] = initialColor
        }
        viewSpecificState["validatedProperties"] = properties
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let colorBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Color ?? initialColor },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["value"] = newValue
                newState["validatedProperties"] = properties // Include validated properties per ActionUI guidelines
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let title = properties["title"] as? String ?? "Color"
        
        return SwiftUI.ColorPicker(title, selection: colorBinding)
    }
}
