import SwiftUI

struct ActionUIView: SwiftUI.View {
        
    let element: any ActionUIElement
    let state: Binding<[Int: Any]>
    let windowUUID: String
    
    var body: AnyView {
        let registry = ActionUIRegistry.shared
        let validatedProperties = registry.getValidatedProperties(element: element, state: state)
        let baseView = registry.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        return registry.applyModifiers(to: baseView, properties: validatedProperties, element: element, state: state)
    }
}
