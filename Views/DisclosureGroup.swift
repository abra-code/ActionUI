/*
 Sample JSON for DisclosureGroup:
 {
   "type": "DisclosureGroup",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "label": "Details",  // Non-optional: String for the disclosure label; defaults to "" if missing
     "children": [
       { "type": "Text", "properties": { "text": "Content" } }
     ], // Required: Array of child views
     "isExpanded": true   // Optional: Boolean for initial expanded state; if absent, uses false
   }
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
   // Design Decision: Removed the 'isExpanded' modifier and DisclosureGroupRepresentable protocol, as the Binding handles state changes, and actions are triggered via actionHandler in the Binding's set block. This aligns with SwiftUI's self-handling behavior and avoids redundant state management.
 }
*/

import SwiftUI

struct DisclosureGroup: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["label"] == nil {
            print("Warning: DisclosureGroup requires 'label'; defaulting to ''")
            validatedProperties["label"] = ""
        }
        if validatedProperties["children"] == nil {
            print("Warning: DisclosureGroup requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        } else if let children = validatedProperties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        }
        if validatedProperties["isExpanded"] == nil {
            validatedProperties["isExpanded"] = nil // Optional, handled by Binding
        } else if let isExpanded = validatedProperties["isExpanded"] as? Bool {
            validatedProperties["isExpanded"] = isExpanded
        } else {
            print("Warning: DisclosureGroup isExpanded must be a Boolean; setting to nil")
            validatedProperties["isExpanded"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("DisclosureGroup") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let children = properties["children"] as? [[String: Any]] ?? []
            let label = properties["label"] as? String ?? ""
            let initialExpanded = properties["isExpanded"] as? Bool
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["isExpanded": initialExpanded ?? false]
            }
            let expandedBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["isExpanded"] as? Bool ?? false },
                set: { newValue in
                    state.wrappedValue[element.id] = ["isExpanded": newValue]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                DisclosureGroup(isExpanded: expandedBinding) {
                    ForEach(children.indices, id: \.self) { index in
                        ViewBuilderRegistry.shared.buildView(from: children[index], state: state, windowUUID: windowUUID)
                    }
                } label: {
                    Text(label)
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No modifiers needed for isExpanded; handled by Binding and actionHandler
    }
}
