/*
 Sample JSON for KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Animating" } },
     "keyframes": { "0%": { "opacity": 0.0 }, "100%": { "opacity": 1.0 } }
   }
 }
*/

import SwiftUI

struct KeyframeAnimator: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["content"] == nil {
            print("Warning: KeyframeAnimator requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["keyframes"] == nil {
            validatedProperties["keyframes"] = ["0%": ["opacity": 0.0], "100%": ["opacity": 1.0]]
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        if #available(iOS 17.0, macOS 14.0, *) {
            registry.register("KeyframeAnimator") { element, state, windowUUID in
                let properties = StaticElement.getValidatedProperties(element: element, state: state)
                let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
                let keyframes = properties["keyframes"] as? [String: [String: Double]] ?? ["0%": ["opacity": 0.0], "100%": ["opacity": 1.0]]
                return AnyView(
                    KeyframeAnimator(initialValue: 0) { value in
                        ViewBuilderRegistry.shared.buildView(from: content, state: state, windowUUID: windowUUID)
                            .opacity(keyframes["\(Int(value))%"]?["opacity"] ?? 1.0)
                    } keyframes: {
                        KeyframeTrack(\.self) {
                            for (percent, attrs) in keyframes {
                                Keyframe(percent, transition: .linear) {
                                    attrs.forEach { key, val in
                                        switch key {
                                        case "opacity": return .opacity(val)
                                        default: break
                                        }
                                    }
                                }
                            }
                        }
                    }
                )
            }
        } else {
            registry.register("KeyframeAnimator") { _, _, _ in
                print("Warning: KeyframeAnimator requires iOS 17.0 or macOS 14.0")
                return AnyView(EmptyView())
            }
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers defined; keyframes handled in register
    }
}
