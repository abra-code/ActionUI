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
		View.registerModifiers(registry: registry)
		Text.registerModifiers(registry: registry)
		List.registerModifiers(registry: registry)
		LazyHStack.registerModifiers(registry: registry)
		EmptyView.registerModifiers(registry: registry)
		Grid.registerModifiers(registry: registry)
		TextField.registerModifiers(registry: registry)
		LazyVGrid.registerModifiers(registry: registry)
		Group.registerModifiers(registry: registry)
		HStack.registerModifiers(registry: registry)
		TextEditor.registerModifiers(registry: registry)
		LazyVStack.registerModifiers(registry: registry)
		ComboBox.registerModifiers(registry: registry)
		ZStack.registerModifiers(registry: registry)
		Table.registerModifiers(registry: registry)
		Toggle.registerModifiers(registry: registry)
		VStack.registerModifiers(registry: registry)
		LazyHGrid.registerModifiers(registry: registry)
		DatePicker.registerModifiers(registry: registry)
		Slider.registerModifiers(registry: registry)
		StepSlider.registerModifiers(registry: registry)
		ProgressView.registerModifiers(registry: registry)
		Label.registerModifiers(registry: registry)
		SecureField.registerModifiers(registry: registry)
		ScrollView.registerModifiers(registry: registry)
		Gauge.registerModifiers(registry: registry)
		ColorPicker.registerModifiers(registry: registry)
		Canvas.registerModifiers(registry: registry)
		Map.registerModifiers(registry: registry)
		VideoPlayer.registerModifiers(registry: registry)
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
