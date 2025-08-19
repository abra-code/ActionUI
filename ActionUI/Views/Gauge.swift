/*
 Sample JSON for Gauge:
 {
   "type": "Gauge",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.75,       // Optional: Value (Double), defaults to 0.0
     "label": "Progress", // Optional: String for label, defaults to nil
     "style": "accessoryCircular", // Optional: "accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity" (iOS/macOS/visionOS); defaults to "accessoryCircular"
     "range": { "min": 0.0, "max": 100.0 } // Optional: Dictionary with min/max values, defaults to 0.0 to 1.0
   }
   // Note: These properties are specific to Gauge. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Gauge: ActionUIViewConstruction {
    // Design decision: Defines valueType as Double to reflect the gauge's value for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { Double.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate value
        if let value = validatedProperties["value"] as? Double {
            validatedProperties["value"] = value
        } else if validatedProperties["value"] != nil {
            logger.log("Gauge value must be a Double; defaulting to 0.0", .warning)
            validatedProperties["value"] = 0.0
        }
        
        // Validate label
        if let label = validatedProperties["label"] as? String {
            validatedProperties["label"] = label
        } else if validatedProperties["label"] != nil {
            logger.log("Gauge label must be a String; defaulting to nil", .warning)
            validatedProperties["label"] = nil
        }
        
        // Validate style
        let validStyles = ["accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity"]
        if let style = validatedProperties["style"] as? String, !validStyles.contains(style) {
            logger.log("Gauge style '\(style)' invalid on \(String(describing: ProcessInfo.processInfo.operatingSystemVersionString)); defaulting to 'accessoryCircular'", .warning)
            validatedProperties["style"] = "accessoryCircular"
        }
        if validatedProperties["style"] == nil {
            validatedProperties["style"] = "accessoryCircular"
        }
        
        // Validate range
        if let range = validatedProperties["range"] as? [String: Double] {
            var validatedRange: [String: Double] = [:]
            if let min = range["min"], let max = range["max"], min <= max {
                validatedRange["min"] = min
                validatedRange["max"] = max
                validatedProperties["range"] = validatedRange
            } else {
                logger.log("Gauge range must have valid min/max Doubles with min <= max; defaulting to 0.0...1.0", .warning)
                validatedProperties["range"] = ["min": 0.0, "max": 1.0]
            }
        } else if validatedProperties["range"] != nil {
            logger.log("Gauge range must be a dictionary with min/max Doubles; defaulting to 0.0...1.0", .warning)
            validatedProperties["range"] = ["min": 0.0, "max": 1.0]
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let initialValue = (properties["value"] as? Double) ?? 0.0
        let value = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double ?? initialValue
        let range = properties["range"] as? [String: Double] ?? ["min": 0.0, "max": 1.0]
        let min = range["min"] ?? 0.0
        let max = range["max"] ?? 1.0
        
        return SwiftUI.Gauge(value: value, in: min...max) {
            if let label = properties["label"] as? String {
                SwiftUI.Text(label)
            } else {
                SwiftUI.EmptyView()
            }
        }
        .onChange(of: (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Double) { newValue in
            Task { @MainActor in
                if let newValue = newValue, (min...max).contains(newValue) {
                    state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
                        ["value": newValue, "validatedProperties": properties],
                        uniquingKeysWith: { _, new in new }
                    )
                    if let actionID = properties["actionID"] as? String {
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
        var modifiedView = view
        if let style = properties["style"] as? String {
            switch style {
            case "accessoryLinear":
                modifiedView = modifiedView.gaugeStyle(.accessoryLinear)
            case "accessoryLinearCapacity":
                modifiedView = modifiedView.gaugeStyle(.accessoryLinearCapacity)
            case "accessoryCircularCapacity":
                modifiedView = modifiedView.gaugeStyle(.accessoryCircularCapacity)
            default:
                modifiedView = modifiedView.gaugeStyle(.accessoryCircular)
            }
        }
        return modifiedView
    }
}
