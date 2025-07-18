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
 }
*/

import SwiftUI

struct PhaseAnimator: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        if #available(iOS 17.0, macOS 14.0, *) {
            registry.register("PhaseAnimator") { element, state, windowUUID in
                let properties = StaticElement.getValidatedProperties(element: element, state: state)
                let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
                let values = properties["values"] as? [Double] ?? [0.0, 1.0]
                let trigger = properties["trigger"] as? String ?? "onAppear"
                return AnyView(
                    PhaseAnimator(values) { value in
                        ViewBuilderRegistry.shared.buildView(from: content, state: state, windowUUID: windowUUID)
                            .scaleEffect(value)
                    } trigger: {
                        switch trigger {
                        case "onAppear": return .onAppear
                        default: return .onAppear
                        }
                    }
                )
            }
        } else {
            registry.register("PhaseAnimator") { _, _, _ in
                print("Warning: PhaseAnimator requires iOS 17.0 or macOS 14.0")
                return AnyView(EmptyView())
            }
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        if #available(iOS 17.0, macOS 14.0, *) {
            registry.register("trigger") { view, properties in
                guard let trigger = properties["trigger"] as? String else { return view }
                return AnyView(view.phaseAnimatorTrigger(trigger == "onAppear" ? .onAppear : .onAppear))
            }
        }
    }
}
