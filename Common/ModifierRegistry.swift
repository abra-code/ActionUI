import SwiftUI

class ModifierRegistry {
    typealias Modifier = (AnyView, [String: Any]) -> AnyView
    private var modifiers: [String: Modifier] = [:]
    
    static let shared = ModifierRegistry()
    
    private init() {
        // No initial registrations; rely on external calls
    }
    
	static func setupModifiers() {
		let registry = ModifierRegistry.shared
		AsyncImage.registerModifiers(registry: registry)
		Button.registerModifiers(registry: registry)
		Canvas.registerModifiers(registry: registry)
		ColorPicker.registerModifiers(registry: registry)
//		ComboBox.registerModifiers(registry: registry) DISABLED experiment
		DatePicker.registerModifiers(registry: registry)
		DisclosureGroup.registerModifiers(registry: registry)
		Divider.registerModifiers(registry: registry)
		EmptyView.registerModifiers(registry: registry)
		Form.registerModifiers(registry: registry)
		Gauge.registerModifiers(registry: registry)
		Grid.registerModifiers(registry: registry)
		Group.registerModifiers(registry: registry)
		HStack.registerModifiers(registry: registry)
		Image.registerModifiers(registry: registry)
		KeyframeAnimator.registerModifiers(registry: registry)
		Label.registerModifiers(registry: registry)
		LazyHGrid.registerModifiers(registry: registry)
		LazyHStack.registerModifiers(registry: registry)
		LazyVGrid.registerModifiers(registry: registry)
		LazyVStack.registerModifiers(registry: registry)
		Link.registerModifiers(registry: registry)
		List.registerModifiers(registry: registry)
		Map.registerModifiers(registry: registry)
		Menu.registerModifiers(registry: registry)
		NavigationLink.registerModifiers(registry: registry)
		NavigationView.registerModifiers(registry: registry)
		PhaseAnimator.registerModifiers(registry: registry)
		Picker.registerModifiers(registry: registry)
		ProgressView.registerModifiers(registry: registry)
		ScrollView.registerModifiers(registry: registry)
		ScrollViewReader.registerModifiers(registry: registry)
		Section.registerModifiers(registry: registry)
		SecureField.registerModifiers(registry: registry)
		ShareLink.registerModifiers(registry: registry)
		Slider.registerModifiers(registry: registry)
		Spacer.registerModifiers(registry: registry)
		StepSlider.registerModifiers(registry: registry)
		TabBarItem.registerModifiers(registry: registry)
		Table.registerModifiers(registry: registry)
		TabView.registerModifiers(registry: registry)
		Text.registerModifiers(registry: registry)
		TextEditor.registerModifiers(registry: registry)
		TextField.registerModifiers(registry: registry)
		Toggle.registerModifiers(registry: registry)
		VideoPlayer.registerModifiers(registry: registry)
		View.registerModifiers(registry: registry)
		VStack.registerModifiers(registry: registry)
		ZStack.registerModifiers(registry: registry)
//		macOS 26 & iOS 26?:
//		WebView.registerModifiers(registry: registry)
//		RichTextEditor.registerModifiers(registry: registry)
		// Add other views as needed
	}

    func register(_ name: String, modifier: @escaping Modifier) {
        modifiers[name] = modifier
    }
    
    func applyModifiers(to view: AnyView, properties: [String: Any]) -> AnyView {
        var modifiedView = view
        for (key, value) in properties {
            if let modifier = modifiers[key] {
                modifiedView = modifier(modifiedView, [key: value])
            }
        }
        return modifiedView
    }
}
