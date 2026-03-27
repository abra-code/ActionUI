// Sources/ActionUIView.swift
/*
 ActionUIView.swift

 Constructs a SwiftUI view from an ActionUIElementBase, using ViewModel for state and ActionUIRegistry for view building and modifiers.
*/

import SwiftUI

@MainActor
public struct ActionUIView: SwiftUI.View /*, Equatable*/ {
    let element: any ActionUIElementBase
    @ObservedObject var model: ViewModel
    let windowUUID: String
 
    init(element: any ActionUIElementBase, model: ViewModel, windowUUID: String) {
        self.element = element
        self.model = model
        self.windowUUID = windowUUID
    }

    // Builds the SwiftUI view using validated properties from ViewModel
    public var body: some SwiftUI.View {
        let registry = ActionUIRegistry.shared
        let validatedProperties = registry.getValidatedProperties(element: element, model: model)
        let baseView = registry.buildView(
            for: element,
            model: model,
            windowUUID: windowUUID,
            validatedProperties: validatedProperties
        )
        // Apply modifiers and return the final view
        return registry.applyViewModifiers(
            to: baseView,
            properties: validatedProperties,
            element: element,
            model: model,
            windowUUID: windowUUID
        )
    }
    
    #if false // incorrect equality function causes views not to refresh when they should be after mutating states
    // Equatable conformance to compare ActionUIView instances
    public static func == (lhs: ActionUIView, rhs: ActionUIView) -> Bool {
        guard lhs.element.id == rhs.element.id,
              lhs.element.type == rhs.element.type,
              lhs.windowUUID == rhs.windowUUID,
              PropertyComparison.areValuesEqual(lhs.model.value, rhs.model.value),
              PropertyComparison.arePropertiesEqual(lhs.element.properties, rhs.element.properties),
              PropertyComparison.arePropertiesEqual(lhs.model.states, rhs.model.states)
        else {
            return false
        }

        let lhsSubviews = lhs.element.subviews ?? [:]
        let rhsSubviews = rhs.element.subviews ?? [:]
        guard lhsSubviews.keys.sorted() == rhsSubviews.keys.sorted() else {
            return false
        }

        for key in ["children", "rows", "content", "destination", "sidebar", "detail", "label", "popover", "destinations"] {
            let lhsValue = lhsSubviews[key]
            let rhsValue = rhsSubviews[key]

            switch (lhsValue, rhsValue) {
            case (nil, nil):
                continue
            case (let lhsChildren as [ActionUIElement], let rhsChildren as [ActionUIElement]):
                guard lhsChildren.count == rhsChildren.count,
                      zip(lhsChildren, rhsChildren).allSatisfy({ $0 == $1 }) else {
                    return false
                }
            case (let lhsRows as [[ActionUIElement]], let rhsRows as [[ActionUIElement]]):
                guard lhsRows.count == rhsRows.count,
                      zip(lhsRows, rhsRows).allSatisfy({ zip($0, $1).allSatisfy({ $0 == $1 }) }) else {
                    return false
                }
            case (let lhsChild as ActionUIElement, let rhsChild as ActionUIElement):
                guard lhsChild == rhsChild else {
                    return false
                }
            case (nil, _), (_, nil):
                return false
            default:
                return false // Type mismatch or unsupported type
            }
        }

        return true
    }
    #endif // false
}
