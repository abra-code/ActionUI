// Sources/Views/Gauge.swift
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
    static var valueType: Any.Type { Double.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate value
        if (properties.double(forKey: "value") == nil), properties["value"] != nil {
            logger.log("Gauge value must be a number; defaulting to 0.0", .warning)
            validatedProperties["value"] = nil
        }
        
        // Validate label
        if !(properties["label"] is String?), properties["label"] != nil {
            logger.log("Gauge label must be a String; defaulting to nil", .warning)
            validatedProperties["label"] = nil
        }
        
        // Validate style
        let validStyles = ["accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity"]
        if let style = validatedProperties["style"] as? String {
            if !validStyles.contains(style) {
                logger.log("Gauge style '\(style)' invalid; defaulting to nil", .warning)
                validatedProperties["style"] = nil
            }
        }
        
        // Validate range
        if let range = properties["range"] as? [String: Any] {
            var validatedRange: [String: Double] = [:]
            if let min = range.double(forKey: "min") {
                validatedRange["min"] = min
            } else {
                logger.log("Gauge range.min must be a number; defaulting to 0.0", .warning)
                validatedRange["min"] = 0.0
            }
            if let max = range.double(forKey: "max") {
                validatedRange["max"] = max
            } else {
                logger.log("Gauge range.max must be a number; defaulting to 1.0", .warning)
                validatedRange["max"] = 1.0
            }
            validatedProperties["range"] = validatedRange
        } else if properties["range"] != nil {
            logger.log("Gauge range must be a dictionary with min/max; defaulting to 0.0...1.0", .warning)
            validatedProperties["range"] = ["min": 0.0, "max": 1.0]
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double ?? 0.0
        let range = properties["range"] as? [String: Double] ?? ["min": 0.0, "max": 1.0]
        let min = range["min"] ?? 0.0
        let max = range["max"] ?? 1.0
        
        let valueBinding = Binding(
            get: { model.value as? Double ?? initialValue },
            set: { newValue in
                if (min...max).contains(newValue) {
                    model.value = newValue
                    if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                } else {
                    logger.log("Gauge value \(newValue) out of range \(min)...\(max); ignoring", .warning)
                }
            }
        )
        
        return SwiftUI.Gauge(value: valueBinding.wrappedValue, in: min...max) {
            if let label = properties["label"] as? String {
                SwiftUI.Text(label)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElement, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
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
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        let initialValue = (model.validatedProperties.double(forKey: "value")) ?? 0.0
        return initialValue
    }
}
