/*
 Sample JSON for DatePicker:
 {
   "type": "DatePicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Select Date", // Optional: String for label, defaults to "Date"
     "displayStyle": "automatic", // Optional: "automatic" (iOS/macOS/visionOS), "compact" (iOS/macOS/visionOS), "graphical" (iOS/macOS/visionOS), "stepperField" (macOS only), "field" (macOS only); defaults to "automatic"
     "range": { "start": "2023-01-01", "end": "2025-12-31" }, // Optional: Dictionary with start/end dates (ISO 8601 strings)
     "selectedDate": "2024-07-16" // Optional: Initial selected date (ISO 8601 string)
   }
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct DatePicker: ActionUIViewConstruction {
    // Design decision: Defines valueType as Date to support type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { Date.self }
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        // Validate label
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Date"
        }
        
        // Validate displayStyle
        #if os(macOS)
        let validStyles = ["automatic", "compact", "graphical", "stepperField", "field"]
        #else
        let validStyles = ["automatic", "compact", "graphical"]
        #endif
        if let displayStyle = validatedProperties["displayStyle"] as? String, !validStyles.contains(displayStyle) {
            print("Warning: DatePicker displayStyle '\(displayStyle)' invalid on \(ProcessInfo.processInfo.operatingSystemVersionString); defaulting to 'automatic'")
            validatedProperties["displayStyle"] = "automatic"
        }
        if validatedProperties["displayStyle"] == nil {
            validatedProperties["displayStyle"] = "automatic"
        }
        
        // Validate range
        if let range = validatedProperties["range"] as? [String: String] {
            var validatedRange: [String: Date] = [:]
            let dateFormatter = ISO8601DateFormatter()
            if let start = range["start"], let date = dateFormatter.date(from: start) {
                validatedRange["start"] = date
            }
            if let end = range["end"], let date = dateFormatter.date(from: end) {
                validatedRange["end"] = date
            }
            if !validatedRange.isEmpty, let start = validatedRange["start"], let end = validatedRange["end"], start <= end {
                validatedProperties["range"] = validatedRange
            } else {
                print("Warning: DatePicker range must have valid start/end ISO 8601 dates with start <= end; ignoring")
                validatedProperties["range"] = nil
            }
        } else if validatedProperties["range"] != nil {
            print("Warning: DatePicker range must be a dictionary with start/end ISO 8601 strings; ignoring")
            validatedProperties["range"] = nil
        }
        
        // Validate selectedDate
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
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        let initialDate = (properties["selectedDate"] as? Date) ?? Date()
        // Initialize state if not set
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": initialDate, "validatedProperties": properties]
        }
        
        let dateBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? Date ?? initialDate },
            set: { newValue in
                state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
                    ["value": newValue, "validatedProperties": properties],
                    uniquingKeysWith: { _, new in new }
                )
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let label = properties["label"] as? String ?? "Date"
        let rangeDict = properties["range"] as? [String: Date]
        let dateRange: ClosedRange<Date>? = {
            if let start = rangeDict?["start"], let end = rangeDict?["end"], start <= end {
                return start...end
            }
            return nil
        }()
        
        if let range = dateRange {
            return SwiftUI.DatePicker(label, selection: dateBinding, in: range, displayedComponents: .date)
        } else {
            return SwiftUI.DatePicker(label, selection: dateBinding, displayedComponents: .date)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any]) -> any SwiftUI.View = { view, properties in
        var modifiedView = view
        if let displayStyle = properties["displayStyle"] as? String {
            switch displayStyle {
            case "compact":
                modifiedView = modifiedView.datePickerStyle(.compact)
            case "graphical":
                modifiedView = modifiedView.datePickerStyle(.graphical)
            case "stepperField":
                #if os(macOS)
                modifiedView = modifiedView.datePickerStyle(.stepperField)
                #else
                print("Warning: stepperField DatePickerStyle unavailable on iOS/visionOS/MacCatalyst; using compact")
                modifiedView = modifiedView.datePickerStyle(.compact)
                #endif
            case "field":
                #if os(macOS)
                modifiedView = modifiedView.datePickerStyle(.field)
                #else
                print("Warning: field DatePickerStyle unavailable on iOS/visionOS/MacCatalyst; using compact")
                modifiedView = modifiedView.datePickerStyle(.compact)
                #endif
            default:
                modifiedView = modifiedView.datePickerStyle(.automatic)
            }
        }
        return modifiedView
    }
}
