// SwiftUI rendering of Gauge; its portable part is in Core/Elements/Gauge.swift.

import SwiftUI

extension Gauge: ActionUISwiftUIRenderer {
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
}
