/*
 Sample JSON for TabView:
 {
   "type": "TabView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "children": [
       { "type": "TabBarItem", "properties": { "title": "Home", "content": { "type": "Text", "properties": { "text": "Home" } } } }
     ], // Required: Array of TabBarItem views
     "selection": 0 // Optional: Integer for selected tab index, defaults to 0
   }
   // Note: These properties are specific to TabView. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct TabView: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["children"] == nil {
            print("Warning: TabView requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        if let selection = validatedProperties["selection"] as? Int {
            validatedProperties["selection"] = selection
        } else if validatedProperties["selection"] != nil {
            print("Warning: TabView selection must be an Integer; defaulting to 0")
            validatedProperties["selection"] = 0
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("TabView") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let children = properties["children"] as? [[String: Any]] ?? []
            let initialSelection = (properties["selection"] as? Int) ?? 0
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["selection": initialSelection]
            }
            let selectionBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["selection"] as? Int ?? initialSelection },
                set: { newValue in
                    state.wrappedValue[element.id] = ["selection": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                TabView(selection: selectionBinding) {
                    ForEach(children.indices, id: \.self) { index in
                        ViewBuilderRegistry.shared.buildView(from: children[index], state: state, windowUUID: windowUUID)
                    }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("selection") { view, properties in
            guard let selection = properties["selection"] as? Int else { return view }
            if let tabView = view as? TabViewRepresentable {
                tabView.selectedIndex = selection
            }
            return view
        }
    }
}
