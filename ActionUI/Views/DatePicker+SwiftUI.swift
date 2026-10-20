// SwiftUI rendering of DatePicker; its portable part is in Core/Elements/DatePicker.swift.

import SwiftUI

extension DatePicker: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let initialDate = Self.initialValue(model) as? Date ?? Date()
        
        // Hoisted out of the binding: its main-actor closures capture only this Sendable String?,
        // not the non-Sendable [String: Any] properties payload.
        let valueChangeActionID = props.valueChangeActionID
        let dateBinding = mainActorBinding(
            get: { model.value as? Date ?? initialDate },
            set: { newValue in
                guard model.value as? Date != newValue else {
                    return
                }
                // Use DispatchQueue.main.async to guarantee deferred execution and avoid
                // "publishing changes from within view updates" warning
                DispatchQueue.main.async {
                    model.value = newValue
                    if let valueChangeActionID {
                        ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let title = props.title

        var startDate: Date?
        var endDate: Date?
        if let range = props.range {
            if let date = DateHelper.parseDate(from: range.start) {
                startDate = date
            }
            if let date = DateHelper.parseDate(from: range.end) {
                endDate = date
            }
        }
        
        let dateRange: ClosedRange<Date>? = {
            if let start = startDate, let end = endDate, start <= end {
                return start...end
            }
            return nil
        }()
        
        let components = Self.displayedComponents(from: props.displayedComponents?.rawValue)

        if let range = dateRange {
            return SwiftUI.DatePicker(title, selection: dateBinding, in: range, displayedComponents: components)
        } else {
            return SwiftUI.DatePicker(title, selection: dateBinding, displayedComponents: components)
        }
    }

    /// Maps the JSON `displayedComponents` string to SwiftUI `DatePickerComponents`.
    /// `nil`/`"date"` -> `.date` (default, date-only); `"hourAndMinute"` -> a time
    /// (hour+minute) picker; `"dateAndTime"` -> a combined `[.date, .hourAndMinute]`
    /// picker. Any unrecognized value falls back to `.date`.
    static func displayedComponents(from raw: String?) -> SwiftUI.DatePickerComponents {
        switch raw {
        case "hourAndMinute":
            return .hourAndMinute
        case "dateAndTime":
            return [.date, .hourAndMinute]
        default:
            return .date
        }
    }

    /// True when the mode carries a time-of-day component (so the value-bridge
    /// serializes a full ISO datetime rather than a bare "YYYY-MM-DD").
    static func isTimeBearing(_ raw: String?) -> Bool {
        raw == "hourAndMinute" || raw == "dateAndTime"
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        switch Props(properties).displayStyle {
        case .compact:
            modifiedView = modifiedView.datePickerStyle(.compact)
        case .graphical:
            modifiedView = modifiedView.datePickerStyle(.graphical)
        case .stepperField:
            #if os(macOS)
            modifiedView = modifiedView.datePickerStyle(.stepperField)
            #else
            // Not on this platform: the default style, as for an unknown name.
            modifiedView = modifiedView.datePickerStyle(.automatic)
            #endif
        case .field:
            #if os(macOS)
            modifiedView = modifiedView.datePickerStyle(.field)
            #else
            // Not on this platform: the default style, as for an unknown name.
            modifiedView = modifiedView.datePickerStyle(.automatic)
            #endif
        case .automatic, nil:
            modifiedView = modifiedView.datePickerStyle(.automatic)
        }
        return modifiedView
    }
}
