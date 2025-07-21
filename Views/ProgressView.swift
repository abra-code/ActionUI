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
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let value = validatedProperties["value"] as? Double
        
        return AnyView(
            SwiftUI.ProgressView(value: value)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.overlay(SwiftUI.Text(label), alignment: .center))
        }
        return modifiedView
    }
}
