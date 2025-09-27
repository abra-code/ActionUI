// Sources/Views/DatePicker.swift
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
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct DatePicker: ActionUIViewConstruction {
    // Design decision: Defines valueType as Date to support type-safe string parsing in ActionUIModel
    static var valueType: Any.Type { Date.self }
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Validate label
        if !(validatedProperties["label"] is String?), validatedProperties["label"] != nil {
            logger.log("DatePicker requires 'label' as String; ignoring", .warning)
            validatedProperties["label"] = nil
        }
        
        // Validate displayStyle
        #if os(macOS)
        let validStyles = ["automatic", "compact", "graphical", "stepperField", "field"]
        #else
        let validStyles = ["automatic", "compact", "graphical"]
        #endif
        if let displayStyle = validatedProperties["displayStyle"] as? String {
            if !validStyles.contains(displayStyle) {
                logger.log("DatePicker displayStyle '\(displayStyle)' invalid on \(ProcessInfo.processInfo.operatingSystemVersionString); ignoring", .warning)
                validatedProperties["displayStyle"] = nil
            }
        } else if validatedProperties["displayStyle"] != nil {
            logger.log("DatePicker requires 'displayStyle' as String; ignoring", .warning)
            validatedProperties["displayStyle"] = nil
        }
        
        // Validate range (lightweight)
        if let range = validatedProperties["range"] as? [String: String] {
            var isValid = true
            if range["start"] == nil {
                logger.log("DatePicker range.start is not specified; ignoring range", .warning)
                isValid = false
            }
            if range["end"] == nil {
                logger.log("DatePicker range.end is not not specified; ignoring range", .warning)
                isValid = false
            }
            if !isValid  {
                validatedProperties["range"] = nil
            }
        } else if validatedProperties["range"] != nil {
            logger.log("DatePicker requires 'range' as [String: String]; ignoring", .warning)
            validatedProperties["range"] = nil
        }
        
        // Validate selectedDate
        if !(validatedProperties["selectedDate"] is String?), validatedProperties["selectedDate"] != nil {
            logger.log("DatePicker selectedDate is not a string; ignoring", .warning)
            validatedProperties["selectedDate"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let initialDate = Self.initialValue(model) as? Date ?? Date()
        
        let dateBinding = Binding(
            get: { model.value as? Date ?? initialDate },
            set: { newValue in
                model.value = newValue
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        let label = properties["label"] as? String ?? "Date"

        var startDate: Date?
        var endDate: Date?
        if let range = properties["range"] as? [String: String] {
            let dateFormatter = ISO8601DateFormatter()
            if let start = range["start"], let date = dateFormatter.date(from: start) {
                startDate = date
            }
            if let end = range["end"], let date = dateFormatter.date(from: end) {
                endDate = date
            }
        }
        
        let dateRange: ClosedRange<Date>? = {
            if let start = startDate, let end = endDate, start <= end {
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
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
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
                logger.log("stepperField DatePickerStyle unavailable on iOS/visionOS/MacCatalyst; using compact", .warning)
                modifiedView = modifiedView.datePickerStyle(.compact)
                #endif
            case "field":
                #if os(macOS)
                modifiedView = modifiedView.datePickerStyle(.field)
                #else
                logger.log("field DatePickerStyle unavailable on iOS/visionOS/MacCatalyst; using compact", .warning)
                modifiedView = modifiedView.datePickerStyle(.compact)
                #endif
            default:
                modifiedView = modifiedView.datePickerStyle(.automatic)
            }
        } else {
            modifiedView = modifiedView.datePickerStyle(.automatic)
        }
        return modifiedView
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initalValue = model.value as? Date {
            return initalValue
        }
        let dateFormatter = ISO8601DateFormatter()
        let dateString = model.validatedProperties["selectedDate"] as? String ?? ""
        let initialDate = dateFormatter.date(from: dateString) ?? Date()
        return initialDate
    }
}
