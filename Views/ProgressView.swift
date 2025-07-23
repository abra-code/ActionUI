/*
 Sample JSON for ProgressView:
 {
   "type": "ProgressView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.5,        // Optional: Progress value (Double 0.0 to 1.0), defaults to nil (indeterminate)
     "label": "Loading",  // Optional: String for label, defaults to nil
   }
   // Note: These properties are specific to ProgressView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ProgressView: ActionUIViewConstruction {
    // Design decision: Defines valueType as Double to reflect progress value for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { Double.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = View.validateProperties(properties)
        
        if let value = validatedProperties["value"] as? Double, (0.0...1.0).contains(value) {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            print("Warning: ProgressView value must be between 0.0 and 1.0; defaulting to nil")
            validatedProperties["value"] = nil
        }
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let initialValue = (validatedProperties["value"] as? Double) ?? 0.0
        let valueBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.ProgressView(value: valueBinding)
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.overlay(SwiftUI.Text(label), alignment: .center))
        }
        return modifiedView
    }
}
