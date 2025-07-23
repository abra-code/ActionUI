/*
 Sample JSON for PhaseAnimator:
 {
   "type": "PhaseAnimator",
   "id": 1,
   "properties": {
     "content": { "type": "Text", "properties": { "text": "Animating" } },
     "values": [0.0, 1.0, 2.0],
     "trigger": "onAppear"
   }
   // Note: These properties are specific to PhaseAnimator. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct PhaseAnimator: ActionUIViewConstruction {
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["content"] == nil {
            print("Warning: PhaseAnimator requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if let values = validatedProperties["values"] as? [Double] {
            validatedProperties["values"] = values
        }
        if validatedProperties["trigger"] == nil {
            validatedProperties["trigger"] = "onAppear"
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        if #available(iOS 17.0, macOS 14.0, *) {
            let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let values = validatedProperties["values"] as? [Double] ?? [0.0, 1.0]
            
            return AnyView(
                SwiftUI.PhaseAnimator(values) { value in
                    ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
                } trigger: {
                    EmptyView()
                }
            )
        } else {
            print("Warning: PhaseAnimator requires iOS 17.0 or macOS 14.0")
            return AnyView(SwiftUI.EmptyView())
        }
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if #available(iOS 17.0, macOS 14.0, *) {
            if let trigger = properties["trigger"] as? String {
                modifiedView = AnyView(modifiedView.phaseAnimatorTrigger(trigger == "onAppear" ? .onAppear : .onAppear))
            }
        }
        return modifiedView
    }
}
