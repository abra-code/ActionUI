// Sources/ActionUIView.swift
import SwiftUI

struct ActionUIView: SwiftUI.View, Equatable {
    let element: any ActionUIElement
    let state: Binding<[Int: Any]>
    let windowUUID: String
    
    var body: some SwiftUI.View {
        let registry = ActionUIRegistry.shared
        let validatedProperties = registry.getValidatedProperties(element: element, state: state)
        let baseView = registry.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        return registry.applyModifiers(to: baseView, properties: validatedProperties, element: element, state: state)
    }
    
    // Equatable conformance: Compare element, relevant state, and windowUUID
    static func == (lhs: ActionUIView, rhs: ActionUIView) -> Bool {
        // Compare element.id, element.type, windowUUID, and element.properties
        guard lhs.element.id == rhs.element.id,
              lhs.element.type == rhs.element.type,
              lhs.windowUUID == rhs.windowUUID,
              PropertyComparison.arePropertiesEqual(lhs.element.properties, rhs.element.properties) else {
            return false
        }
        
        // Compare relevant state for the element
        let lhsState = (lhs.state.wrappedValue[lhs.element.id] as? [String: Any]) ?? [:]
        let rhsState = (rhs.state.wrappedValue[rhs.element.id] as? [String: Any]) ?? [:]
        guard PropertyComparison.arePropertiesEqual(lhsState, rhsState) else {
            return false
        }
        
        // Compare subviews
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
