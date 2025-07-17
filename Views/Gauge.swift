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
   // Note: These properties are specific to Gauge. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Gauge: StaticElement, ViewBuilder {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Gauge") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let value = (properties["value"] as? Double) ?? 0.0
            return AnyView(
                Gauge(value: value) {
                    if let label = properties["label"] as? String {
                        Text(label)
                    } else {
                        EmptyView()
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("style") { view, properties in
            guard let style = properties["style"] as? String else { return view }
            let gaugeStyle = {
                switch style {
                case "accessoryLinear": return GaugeStyle.accessoryLinear
                case "circular": return GaugeStyle.circular
                case "linear": return GaugeStyle.linear
                default: return GaugeStyle.accessoryCircular
                }
            }()
            return AnyView(view.gaugeStyle(gaugeStyle))
        }
    }
}
