/*
 Sample JSON for KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Animating" } },
     "keyframes": { "0%": { "opacity": 0.0 }, "100%": { "opacity": 1.0 } }
   }
   // Note: These properties are specific to KeyframeAnimator. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct KeyframeAnimator: ActionUIViewElement {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        if #available(iOS 17.0, macOS 14.0, *) {
            let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let keyframes = validatedProperties["keyframes"] as? [String: [String: Double]] ?? ["0%": ["opacity": 0.0], "100%": ["opacity": 1.0]]
            
            return AnyView(
                SwiftUI.KeyframeAnimator(initialValue: 0) { value in
                    ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
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
        } else {
            print("Warning: KeyframeAnimator requires iOS 17.0 or macOS 14.0")
            return AnyView(SwiftUI.EmptyView())
        }
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // Keyframes handled in buildElement
    }
}
