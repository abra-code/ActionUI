/*
 Sample JSON for Stepper:
 {
   "type": "Stepper",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "value": 5.0,        // Optional: Initial value (Double), defaults to 0.0
     "range": { "min": 0.0, "max": 10.0 }, // Optional: Dictionary with min/max values; no range clamping if omitted
     "step": 1.0,         // Optional: Step increment (Double), defaults to 1.0
     "label": "Quantity", // Optional: Static string label; ignored when labelFormat is set
     "labelFormat": "Quantity: %.0f", // Optional: printf-style format string embedding the current value:
                          // exactly one of %d %i %f %F %e %E %g %G (flags - + space # 0, width, precision), plus
                          // any %%. %d and %i show the value truncated to an integer. The number is formatted as
                          // C's printf does, with the user's decimal separator ("2,5" in a German locale).
                          // Any other format (%@, %s, two conversions, the ' flag, a width or precision over 4096)
                          // shows the plain value instead
                          // (NumberPrintf). The same on every platform.
                          // Examples: "Count: %d" -> "Count: 5", "Rating: %.1f" -> "Rating: 2.5",
                          //           "Volume: %g%%" -> "Volume: 50%"
                          // Takes precedence over "label" when both are present.
     "actionID": "stepper.changed", // Optional: String for action triggered on user-initiated value change
   }
   // Note: These properties are specific to Stepper. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, disabled, etc.) are inherited and applied via ActionUIRegistry.shared.applyModifiers.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Stepper {
    /// Stepper's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var initialValue = 0.0
        /// The limits, when both bounds are numbers in order; otherwise the stepper is unbounded.
        var range: ClosedRange<Double>?
        var step = 1.0
        var label = ""
        /// A format for the current value (the renderer applies it); takes precedence over label.
        var labelFormat: String?
        var actionID: String?

        init(_ properties: [String: Any]) {
            initialValue = properties.double(forKey: "value") ?? 0.0
            if let range = properties["range"] as? [String: Any],
               let lo = range.double(forKey: "min"), let hi = range.double(forKey: "max"), lo <= hi {
                self.range = lo...hi
            }
            // Not a positive number: 1.0.
            step = properties.double(forKey: "step").flatMap { $0 > 0 ? $0 : nil } ?? 1.0
            label = properties["label"] as? String ?? ""
            labelFormat = properties["labelFormat"] as? String
            actionID = properties["actionID"] as? String
        }
    }

    /// Formats refused so far, each logged once.
    @MainActor private static var reportedFormats: Set<String> = []

    /// The label a renderer shows: labelFormat with the value in it (NumberPrintf; a format it
    /// refuses shows the plain value and is logged once), else the label property.
    @MainActor
    static func labelText(_ props: Props, value: Double) -> String {
        guard let format = props.labelFormat else { return props.label }
        if let text = NumberPrintf.format(format, value) {
            return text
        }
        if reportedFormats.insert(format).inserted {
            ActionUIModel.shared.logger.log("Stepper: labelFormat \"\(format)\" is not one number format; showing the value", .warning)
        }
        return NumberPrintf.plain(value)
    }

    /// The user stepped the value: stores it and fires actionID with it as context, only when it
    /// differs from the value.
    @MainActor
    static func userSetValue(_ newValue: Double, element: any ActionUIElementBase, model: ViewModel, windowUUID: String, props: Props) {
        guard model.value as? Double != newValue else { return }
        model.value = newValue
        if let actionID = props.actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: newValue)
        }
    }
}

struct Stepper: ActionUIElementSpec {
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
