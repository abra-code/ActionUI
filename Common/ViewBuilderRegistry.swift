
import SwiftUI

protocol ViewBuilder {
    static func register(in registry: ViewBuilderRegistry)
}

class ViewBuilderRegistry {
    private var builders: [String: (UIElement, Binding<[Int: Any]>, String) -> AnyView] = [:]
    
    func register(_ type: String, builder: @escaping (UIElement, Binding<[Int: Any]>, String) -> AnyView) {
        builders[type] = builder
    }
    
    func build(for element: UIElement, state: Binding<[Int: Any]>, windowUUID: String) -> AnyView {
        builders[element.type]?(element, state, windowUUID) ?? AnyView(EmptyView())
    }
    
    static func initRegistry() -> ViewBuilderRegistry {
        let registry = ViewBuilderRegistry()
        AsyncImage.register(in: registry)
        Button.register(in: registry)
//       ComboBox.register(in: registry) DISABLED
        EmptyView.register(in: registry)
        Grid.register(in: registry)
        Group.register(in: registry)
        HStack.register(in: registry)
        Image.register(in: registry)
        List.register(in: registry)
        Picker.register(in: registry)
        Spacer.register(in: registry)
        Table.register(in: registry)
        Text.register(in: registry)
        TextEditor.register(in: registry)
        TextField.register(in: registry)
        Toggle.register(in: registry)
        VStack.register(in: registry)
        ZStack.register(in: registry)
        return registry
    }
}
