/*
 Sample JSON for Gauge:
 {
   "type": "Gauge",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.75,       // Optional: Value (Double 0.0 to 1.0), defaults to 0.0
     "label": "Progress", // Optional: String for label, defaults to nil
     "style": "accessoryCircular" // Optional: "accessoryCircular", "accessoryLinear", "circular", "linear"; defaults to "accessoryCircular"
   }
   // Note: These properties are specific to Gauge. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Gauge: ActionUIViewConstruction {
    // Design decision: Defines valueType as Double to reflect the gauge's value for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { Double.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = View.validateProperties(properties)
        
        if let value = validatedProperties["value"] as? Double, (0.0...1.0).contains(value) {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            print("Warning: Gauge value must be between 0.0 and 1.0; defaulting to 0.0")
            validatedProperties["value"] = 0.0
        }
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = nil
        }
        if let style = validatedProperties["style"] as? String,
           !["accessoryCircular", "accessoryLinear", "circular", "linear"].contains(style) {
            print("Warning: Gauge style '\(style)' invalid; defaulting to 'accessoryCircular'")
            validatedProperties["style"] = "accessoryCircular"
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let initialValue = (validatedProperties["value"] as? Double) ?? 0.0
        
        let valueBinding = Binding(
            get: {
                (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue
            },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.Gauge(value: valueBinding) {
                EmptyView()
            }
        )
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.gaugeLabel(Text(label)))
        }
        if let style = properties["style"] as? String {
            let gaugeStyle = {
                switch style {
                case "accessoryLinear": return GaugeStyle.accessoryLinear
                case "circular": return GaugeStyle.circular
                case "linear": return GaugeStyle.linear
                default: return GaugeStyle.accessoryCircular
                }
            }()
            modifiedView = AnyView(modifiedView.gaugeStyle(gaugeStyle))
        }
        return modifiedView
    }
}
