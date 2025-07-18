
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
		Canvas.register(in: registry)
		ColorPicker.register(in: registry)
//		ComboBox.register(in: registry) DISABLED custom multi-part control experiment
		DatePicker.register(in: registry)
		DisclosureGroup.register(in: registry)
		Divider.register(in: registry)
		EmptyView.register(in: registry)
		Form.register(in: registry)
		Gauge.register(in: registry)
		Grid.register(in: registry)
		Group.register(in: registry)
		HStack.register(in: registry)
		Image.register(in: registry)
		KeyframeAnimator.register(in: registry)
		Label.register(in: registry)
		LazyHGrid.register(in: registry)
		LazyHStack.register(in: registry)
		LazyVGrid.register(in: registry)
		LazyVStack.register(in: registry)
		Link.register(in: registry)
		List.register(in: registry)
		Map.register(in: registry)
		Menu.register(in: registry)
		NavigationLink.register(in: registry)
		NavigationView.register(in: registry)
		PhaseAnimator.register(in: registry)
		Picker.register(in: registry)
		ProgressView.register(in: registry)
		ScrollView.register(in: registry)
		ScrollViewReader.register(in: registry)
		Section.register(in: registry)
		SecureField.register(in: registry)
		ShareLink.register(in: registry)
		Slider.register(in: registry)
		Spacer.register(in: registry)
		StepSlider.register(in: registry)
		TabBarItem.register(in: registry)
		Table.register(in: registry)
		TabView.register(in: registry)
		Text.register(in: registry)
		TextEditor.register(in: registry)
		TextField.register(in: registry)
		Toggle.register(in: registry)
		VideoPlayer.register(in: registry)
//		View.register(in: registry) View is not constructible
		VStack.register(in: registry)
		ZStack.register(in: registry)
//		macOS 26 & iOS 26?:
//		WebView.register(in: registry)
//		RichTextEditor.register(in: registry)

        return registry
    }
}
