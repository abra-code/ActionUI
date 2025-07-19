import SwiftUI

struct ActionUIView: View {
    let element: ActionUIElement
    let state: Binding<[Int: Any]>
    let windowUUID: String
    
    var body: some View {
        let registry = ActionUIRegistry.shared
        let validatedProperties = registry.getValidatedProperties(element: element, state: state)
        let baseView = registry.build(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        return registry.applyModifiers(to: baseView, properties: validatedProperties, type: element.type)
    }
}
