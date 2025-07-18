/*
 Sample JSON for NavigationLink:
 {
   "type": "NavigationLink",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Go to Detail", // Optional: String for label, defaults to "Link"
     "destination": { "type": "Text", "properties": { "text": "Detail" } }, // Required: Nested view
     "isActive": true // Optional: Boolean for active state, defaults to false
   }
   // Note: These properties are specific to NavigationLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct NavigationLink: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            validatedProperties["label"] = "Link"
        }
        if validatedProperties["destination"] == nil {
            print("Warning: NavigationLink requires 'destination'; defaulting to EmptyView")
            validatedProperties["destination"] = ["type": "EmptyView", "properties": [:]]
        }
        if validatedProperties["isActive"] == nil {
            validatedProperties["isActive"] = false
        } else if let isActive = validatedProperties["isActive"] as? Bool {
            validatedProperties["isActive"] = isActive
        } else {
            print("Warning: NavigationLink isActive must be a Boolean; defaulting to false")
            validatedProperties["isActive"] = false
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("NavigationLink") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let label = properties["label"] as? String ?? "Link"
            let destination = properties["destination"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let isActive = properties["isActive"] as? Bool ?? false
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["isActive": isActive]
            }
            let activeBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["isActive"] as? Bool ?? isActive },
                set: { newValue in
                    state.wrappedValue[element.id] = ["isActive": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                NavigationLink(
                    destination: ViewBuilderRegistry.shared.buildView(from: destination, state: state, windowUUID: windowUUID),
                    isActive: activeBinding
                ) {
                    Text(label)
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("isActive") { view, properties in
            guard let isActive = properties["isActive"] as? Bool else { return view }
            if let link = view as? NavigationLinkRepresentable {
                link.isActive = isActive
            }
            return view
        }
    }
}
