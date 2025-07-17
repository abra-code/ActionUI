/*
 Sample JSON for ColorPicker:
 {
   "type": "ColorPicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Pick a Color", // Optional: String for label, defaults to "Color"
     "selectedColor": "#FF0000" // Optional: Initial color (hex string), defaults to clear
   }
   // Note: These properties are specific to ColorPicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ColorPicker: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Color"
        }
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("ColorPicker") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let label = properties["label"] as? String ?? "Color"
            let initialColor = (properties["selectedColor"] as? Color) ?? Color.clear
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": initialColor]
            }
            let colorBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Color ?? initialColor },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                ColorPicker(label, selection: colorBinding)
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("label") { view, properties in
            guard let label = properties["label"] as? String else { return view }
            return AnyView(view.colorPickerStyle(.wheel).overlay(
                Text(label),
                alignment: .top
            ))
        }
    }
}
