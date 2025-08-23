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
        guard lhs.element.id == rhs.element.id,
              lhs.element.type == rhs.element.type,
              lhs.windowUUID == rhs.windowUUID,
              PropertyComparison.arePropertiesEqual(
                lhs.element.properties,
                rhs.element.properties
              ) else {
            return false
        }
        
        // Compare children if present
        let lhsChildren = lhs.element.subviews?["children"] as? [StaticElement]
        let rhsChildren = rhs.element.subviews?["children"] as? [StaticElement]

        if let lhsChildren, let rhsChildren {
            guard lhsChildren.count == rhsChildren.count else { return false }
            let allEqual = zip(lhsChildren, rhsChildren).allSatisfy { $0 == $1 }
            if !allEqual {
                return false
            }
        }
        
        // Compare relevant state for the element
        let lhsState = (lhs.state.wrappedValue[lhs.element.id] as? [String: Any]) ?? [:]
        let rhsState = (rhs.state.wrappedValue[rhs.element.id] as? [String: Any]) ?? [:]
        return PropertyComparison.arePropertiesEqual(lhsState, rhsState) &&
               (lhsChildren == nil) && (rhsChildren == nil)
    }
}
