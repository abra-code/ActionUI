import SwiftUI

class ModifierRegistry {
    typealias Modifier = (AnyView, [String: Any]) -> AnyView
    private var modifiers: [String: Modifier] = [:]
    
    static let shared = ModifierRegistry()
    
    private init() {
        // No initial registrations; rely on external calls
    }
    
    static func setupModifiers() {
		View.registerModifiers()
		Button.registerModifiers()
		AsyncImage.registerModifiers()
		Image.registerModifiers()
		Spacer.registerModifiers()
		Picker.registerModifiers()
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
