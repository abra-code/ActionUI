// Sources/ActionUIView.swift
import SwiftUI

/*
 ActionUIView is the entry point for rendering an ActionUI element in SwiftUI.
 It uses ActionUIRegistry to build and modify the view based on the element's type and properties.
 Equatable conformance ensures efficient view updates by comparing element and model state.
*/

struct ActionUIView: SwiftUI.View, Equatable {
    let element: any ActionUIElement
    @ObservedObject var model: ViewModel
    let windowUUID: String
    
    var body: some SwiftUI.View {
        // Fetch validated properties and build the base view
        let registry = ActionUIRegistry.shared
        let validatedProperties = registry.getValidatedProperties(element: element, model: model)
        let baseView = registry.buildView(
            for: element,
            model: model,
            windowUUID: windowUUID,
            validatedProperties: validatedProperties
        )
        // Apply modifiers and return the final view
        return registry.applyModifiers(
            to: baseView,
            properties: validatedProperties,
            element: element,
            model: model
        )
    }
    
    // Equatable conformance to optimize view updates
    static func == (lhs: ActionUIView, rhs: ActionUIView) -> Bool {
        // Compare element id, type, windowUUID, and properties
        guard lhs.element.id == rhs.element.id,
              lhs.element.type == rhs.element.type,
              lhs.windowUUID == rhs.windowUUID,
              PropertyComparison.areValuesEqual(lhs.model.value, rhs.model.value),
              PropertyComparison.arePropertiesEqual(lhs.element.properties, rhs.element.properties),
              PropertyComparison.arePropertiesEqual(lhs.model.properties, rhs.model.properties),
              PropertyComparison.arePropertiesEqual(lhs.model.validatedProperties, rhs.model.validatedProperties),
              PropertyComparison.arePropertiesEqual(lhs.model.states, rhs.model.states)
               else {
            return false
        }
        
        // Compare subviews for equality
        let lhsSubviews = lhs.element.subviews ?? [:]
        let rhsSubviews = rhs.element.subviews ?? [:]
        guard lhsSubviews.keys.sorted() == rhsSubviews.keys.sorted() else {
            return false
        }
        
        for key in ["children", "rows", "content", "destination", "sidebar", "detail"] {
            let lhsValue = lhsSubviews[key]
            let rhsValue = rhsSubviews[key]
            
            switch (lhsValue, rhsValue) {
            case (nil, nil):
                continue
            case (let lhsChildren as [ViewElement], let rhsChildren as [ViewElement]):
                guard lhsChildren.count == rhsChildren.count,
                      zip(lhsChildren, rhsChildren).allSatisfy({ $0 == $1 }) else {
                    return false
                }
            case (let lhsRows as [[ViewElement]], let rhsRows as [[ViewElement]]):
                guard lhsRows.count == rhsRows.count,
                      zip(lhsRows, rhsRows).allSatisfy({ zip($0, $1).allSatisfy({ $0 == $1 }) }) else {
                    return false
                }
            case (let lhsChild as ViewElement, let rhsChild as ViewElement):
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
}
