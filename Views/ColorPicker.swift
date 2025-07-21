/*
 Sample JSON for ColorPicker:
 {
   "type": "ColorPicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Pick a Color", // Optional: String for label, defaults to "Color"
     "selectedColor": "#FF0000" // Optional: Initial color (hex string), defaults to clear
   }
   // Note: These properties are specific to ColorPicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ColorPicker: ActionUIViewElement {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let initialColor = (validatedProperties["selectedColor"] as? Color) ?? Color.clear
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": initialColor]
        }
        let colorBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Color ?? initialColor },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                   ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.ColorPicker("", selection: colorBinding)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.colorPickerStyle(.wheel).overlay(Text(label), alignment: .top))
        }
        return modifiedView
    }
}
