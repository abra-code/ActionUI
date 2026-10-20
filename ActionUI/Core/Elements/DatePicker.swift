// Core/Elements/DatePicker.swift
/*
 Sample JSON for DatePicker:
 {
   "type": "DatePicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Select Date", // Optional: String for title, defaults to "Date"
     "displayStyle": "automatic", // Optional: "automatic" (iOS/macOS/visionOS), "compact" (iOS/macOS/visionOS), "graphical" (iOS/macOS/visionOS), "stepperField" (macOS only), "field" (macOS only); defaults to "automatic"
     "displayedComponents": "date", // Optional: "date" (default), "hourAndMinute" (time wheel), "dateAndTime" (date+time)
     "range": { "start": "2023-01-01", "end": "2025-12-31" }, // Optional: Dictionary with start/end dates (ISO 8601 strings)
     "selectedDate": "2024-07-16" // Optional: Initial selected value. Accepts "YYYY-MM-DD", "HH:mm", or a full ISO datetime
   }
   // Value serialization: "date" emits "YYYY-MM-DD"; "hourAndMinute"/"dateAndTime" emit a full ISO datetime "YYYY-MM-DDTHH:mm:ss".
   //   Emitted values never carry a zone: they are the local day or local wall-clock time.
   // Input strings (selectedDate, range, values written by a host) mean:
   //   "YYYY-MM-DD" a calendar day; "YYYY-MM-DDTHH:mm[:ss]" wall-clock time in the device's time zone;
   //   "...Z", "...+hh:mm", "...+hhmm" or "...+hh" an instant, shown in the device's time zone (a "date" picker shows its local day);
   //   "HH:mm[:ss]" that wall-clock time today. To give a calendar day, pass "YYYY-MM-DD", not "...T00:00:00Z".
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension DatePicker {
    /// DatePicker's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// "stepperField" and "field" exist on macOS only; elsewhere the renderer uses the default style.
        enum DisplayStyle: String, Sendable, CaseIterable {
            case automatic, compact, graphical, stepperField, field
        }

        enum DisplayedComponents: String, Sendable, CaseIterable {
            case date, hourAndMinute, dateAndTime
        }

        /// The limits as written (date strings); the renderer parses them.
        struct DateRange: Equatable, Sendable {
            var start: String
            var end: String
        }

        var title = "Date"
        var displayStyle: DisplayStyle?
        /// nil is date only.
        var displayedComponents: DisplayedComponents?
        /// Present only when "range" is a dictionary of strings with both "start" and "end".
        var range: DateRange?
        /// The initial date as written; "" when not given (or not a String).
        var selectedDate = ""
        var valueChangeActionID: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? "Date"
            displayStyle = (properties["displayStyle"] as? String).flatMap(DisplayStyle.init(rawValue:))
            displayedComponents = (properties["displayedComponents"] as? String).flatMap(DisplayedComponents.init(rawValue:))
            if let range = properties["range"] as? [String: String],
               let start = range["start"], let end = range["end"] {
                self.range = DateRange(start: start, end: end)
            }
            selectedDate = properties["selectedDate"] as? String ?? ""
            valueChangeActionID = properties["valueChangeActionID"] as? String
        }
    }
}

struct DatePicker: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // Design decision: Defines valueType as Date to support type-safe string parsing in ActionUIModel
    static var valueType: Any.Type = Date.self

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? Date {
            return initialValue
        }
        let dateString = Props(model.properties).selectedDate
        let initialDate = DateHelper.parseDate(from: dateString) ?? Date()
        return initialDate
    }
}
