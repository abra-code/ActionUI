/*
 Sample JSON for DatePicker:
 {
   "type": "DatePicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Select Date", // Optional: String for label, defaults to "Date"
     "displayStyle": "automatic", // Optional: "automatic", "compact", "graphical"; defaults to "automatic"
     "range": { "start": "2023-01-01", "end": "2025-12-31" }, // Optional: Dictionary with start/end dates (ISO 8601 strings)
     "selectedDate": "2024-07-16" // Optional: Initial selected date (ISO 8601 string)
   }
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct DatePicker: ActionUIViewConstruction {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Date"
        }
        if let displayStyle = validatedProperties["displayStyle"] as? String,
           !["automatic", "compact", "graphical"].contains(displayStyle) {
            print("Warning: DatePicker displayStyle '\(displayStyle)' invalid; defaulting to 'automatic'")
            validatedProperties["displayStyle"] = "automatic"
        }
        if let range = validatedProperties["range"] as? [String: String] {
            var validatedRange: [String: Date?] = [:]
            let dateFormatter = ISO8601DateFormatter()
            if let start = range["start"], let date = dateFormatter.date(from: start) {
                validatedRange["start"] = date
            }
            if let end = range["end"], let date = dateFormatter.date(from: end) {
                validatedRange["end"] = date
            }
            if !validatedRange.isEmpty {
                validatedProperties["range"] = validatedRange
            }
        }
        if let selectedDate = validatedProperties["selectedDate"] as? String {
            let dateFormatter = ISO8601DateFormatter()
            if let date = dateFormatter.date(from: selectedDate) {
                validatedProperties["selectedDate"] = date
            } else {
                print("Warning: DatePicker selectedDate '\(selectedDate)' invalid; ignoring")
                validatedProperties["selectedDate"] = nil
            }
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let initialDate = (validatedProperties["selectedDate"] as? Date) ?? Date()
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": initialDate]
        }
        let dateBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Date ?? initialDate },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return AnyView(
            SwiftUI.DatePicker("", selection: dateBinding, displayedComponents: .date)
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let label = properties["label"] as? String {
            modifiedView = AnyView(modifiedView.datePickerLabel(Text(label)))
        }
        if let displayStyle = properties["displayStyle"] as? String {
            let style = {
                switch displayStyle {
                case "compact": return DatePickerStyle.compact
                case "graphical": return DatePickerStyle.graphical
                default: return DatePickerStyle.automatic
                }
            }()
            modifiedView = AnyView(modifiedView.datePickerStyle(style))
        }
        if let range = properties["range"] as? [String: Date?] {
            modifiedView = AnyView(modifiedView.datePickerRange(range["start"]...range["end"]))
        }
        return modifiedView
    }
}
