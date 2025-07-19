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

struct Gauge: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let value = (validatedProperties["value"] as? Double) ?? 0.0
        
        return AnyView(
            SwiftUI.Gauge(value: value) {
                EmptyView()
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
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
