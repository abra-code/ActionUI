// Core/Elements/Gauge.swift
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

struct Gauge: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Double.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Double {
            return initialValue
        }
        return Props(model.properties).initialValue
    }
}
