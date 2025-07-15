import SwiftUI

struct UILibraryView: View {
    let element: UIElement
    let state: Binding<[Int: Any]>
    let dialogGUID: String
    
    var body: some View {
        let baseView = ViewBuilderRegistry.shared.build(for: element, state: state, dialogGUID: dialogGUID)
        return ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties)
    }
}
