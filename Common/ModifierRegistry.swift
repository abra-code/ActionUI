import SwiftUI

class ModifierRegistry {
    typealias Modifier = (AnyView, [String: Any]) -> AnyView
    private var modifiers: [String: Modifier] = [:]
    
    static let shared = ModifierRegistry()
    
    private init() {
        register("padding") { view, properties in
            if let padding = properties["padding"] as? CGFloat {
                return AnyView(view.padding(padding))
            } else if let padding = properties["padding"] as? [String: CGFloat] {
                return AnyView(view.padding(EdgeInsets(
                    top: padding["top"] ?? 0,
                    leading: padding["leading"] ?? 0,
                    bottom: padding["bottom"] ?? 0,
                    trailing: padding["trailing"] ?? 0
                )))
            }
            return view
        }
        register("font") { view, properties in
            if let font = properties["font"] as? String {
                return AnyView(view.font(FontHelper.resolveFont(font)))
            }
            return view
        }
        register("foregroundColor") { view, properties in
            if let color = properties["foregroundColor"] {
                if let resolvedColor = ColorHelper.resolveColor(color) {
                    return AnyView(view.foregroundColor(resolvedColor))
                }
            }
            return view
        }
        register("disabled") { view, properties in
            if let disabled = properties["disabled"] as? Bool {
                return AnyView(view.disabled(disabled))
            }
            return view
        }
        register("hidden") { view, _ in
            AnyView(view.hidden())
        }
        register("pickerStyle") { view, properties in
            if let style = properties["pickerStyle"] as? String {
                switch style {
                case "menu": return AnyView(view.pickerStyle(.menu))
                case "wheel": return AnyView(view.pickerStyle(.wheel))
                case "segmented": return AnyView(view.pickerStyle(.segmented))
                default: return view
                }
            }
            return view
        }
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
