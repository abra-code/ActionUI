// Sources/Views/Gauge.swift
/*
 Sample JSON for Gauge:
 {
   "type": "Gauge",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 0.75,       // Optional: Value (Double), defaults to 0.0
     "title": "Progress", // Optional: String for title, defaults to nil
     "style": "accessoryCircular", // Optional: "accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity" (iOS/macOS/visionOS); defaults to "accessoryCircular"
     "range": { "min": 0.0, "max": 100.0 } // Optional: Dictionary with min/max values, defaults to 0.0 to 1.0
   }
   // Note: These properties are specific to Gauge. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

extension Gauge {
    /// Gauge's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Style: String, Sendable, CaseIterable {
            case accessoryCircular, accessoryCircularCapacity, accessoryLinear, accessoryLinearCapacity
        }

        var initialValue = 0.0
        var min = 0.0
        var max = 1.0
        var title: String?
        var style: Style?
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            initialValue = properties.double(forKey: "value") ?? 0.0
            // A range dictionary: each bound that is not a number is 0 or 1. Bounds out of order
            // (or a range that is not a dictionary) are 0...1.
            if let range = properties["range"] as? [String: Any] {
                let lo = range.double(forKey: "min") ?? 0.0
                let hi = range.double(forKey: "max") ?? 1.0
                if lo <= hi {
                    min = lo
                    max = hi
                }
            }
            title = properties["title"] as? String
            style = (properties["style"] as? String).flatMap(Style.init(rawValue:))
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }

        /// A value the user may set: inside the range.
        func accepts(_ value: Double) -> Bool {
            (min...max).contains(value)
        }
    }
}

struct Gauge: ActionUIViewConstruction {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Double.self
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate value
        if (properties.double(forKey: "value") == nil), properties["value"] != nil {
            logger.log("Gauge value must be a number; defaulting to 0.0", .warning)
            validatedProperties["value"] = nil
        }
        
        // Validate title
        if !(properties["title"] is String?), properties["title"] != nil {
            logger.log("Gauge title must be a String; defaulting to nil", .warning)
            validatedProperties["title"] = nil
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
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialValue = Self.initialValue(model) as? Double ?? 0.0
        let props = Props(properties)
        let min = props.min
        let max = props.max
        
        // Hoisted out of the binding: its main-actor closures capture only this Sendable String?,
        // not the non-Sendable [String: Any] properties payload.
        let valueChangeActionID = props.valueChangeActionID
        let valueBinding = mainActorBinding(
            get: { model.value as? Double ?? initialValue },
            set: { newValue in
                guard model.value as? Double != newValue else {
                    return
                }

                if props.accepts(newValue) {
                    // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                    // "publishing changes from within view updates" warning
                    DispatchQueue.main.async {
                        model.value = newValue
                        if let valueChangeActionID {
                            ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                        }
                    }
                } else {
                    logger.log("Gauge value \(newValue) out of range \(min)...\(max); ignoring", .warning)
                }
            }
        )
        
        return SwiftUI.Gauge(value: valueBinding.wrappedValue, in: min...max) {
            if let title = props.title {
                SwiftUI.Text(title)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        switch Props(properties).style {
        case .accessoryLinear:
            modifiedView = modifiedView.gaugeStyle(.accessoryLinear)
        case .accessoryLinearCapacity:
            modifiedView = modifiedView.gaugeStyle(.accessoryLinearCapacity)
        case .accessoryCircularCapacity:
            modifiedView = modifiedView.gaugeStyle(.accessoryCircularCapacity)
        case .accessoryCircular:
            modifiedView = modifiedView.gaugeStyle(.accessoryCircular)
        case nil:
            break
        }
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return Props(model.properties).initialValue
    }
}
