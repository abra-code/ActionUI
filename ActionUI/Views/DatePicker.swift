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
   // Note: These properties are specific to DatePicker. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
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
        
        // Validate range
        if let range = validatedProperties["range"] as? [String: String] {
            var validatedRange: [String: Date] = [:]
            let dateFormatter = ISO8601DateFormatter()
            var isValid = true
            if let start = range["start"], let date = dateFormatter.date(from: start) {
                validatedRange["start"] = date
            } else if range["start"] != nil {
                logger.log("DatePicker range.start '\(String(describing: range["start"]))' invalid ISO 8601 string; ignoring range", .warning)
                isValid = false
            }
            if let end = range["end"], let date = dateFormatter.date(from: end) {
                validatedRange["end"] = date
            } else if range["end"] != nil {
                logger.log("DatePicker range.end '\(String(describing: range["end"]))' invalid ISO 8601 string; ignoring range", .warning)
                isValid = false
            }
            if isValid && !validatedRange.isEmpty {
                validatedProperties["range"] = validatedRange
            } else {
                validatedProperties["range"] = nil
            }
        } else if validatedProperties["range"] != nil {
            logger.log("DatePicker requires 'range' as [String: String]; ignoring", .warning)
            validatedProperties["range"] = nil
        }
        
        // Validate selectedDate
        if let selectedDate = validatedProperties["selectedDate"] as? String {
            let dateFormatter = ISO8601DateFormatter()
            if dateFormatter.date(from: selectedDate) == nil {
                logger.log("DatePicker selectedDate '\(selectedDate)' invalid ISO 8601 string; ignoring", .warning)
                validatedProperties["selectedDate"] = nil
            } else {
                validatedProperties["selectedDate"] = dateFormatter.date(from: selectedDate)
            }
        } else if validatedProperties["selectedDate"] != nil {
            logger.log("DatePicker requires 'selectedDate' as String; ignoring", .warning)
            validatedProperties["selectedDate"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        let dateFormatter = ISO8601DateFormatter()
        let initialDate = (properties["selectedDate"] as? Date) ?? Date()
        
        // Initialize state if not set
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [:]
        }
        state.wrappedValue[element.id] = (state.wrappedValue[element.id] as? [String: Any] ?? [:]).merging(
            ["value": initialDate, "validatedProperties": properties],
            uniquingKeysWith: { _, new in new }
        )
        
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
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, properties, logger in
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
}
