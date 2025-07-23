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
   // Note: These properties are specific to DisclosureGroup. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct DisclosureGroup: ActionUIViewConstruction {
    // Design decision: Defines valueType as Bool to reflect isExpanded state for type-safe string parsing in ActionUIModel
    static var valueType: Any.Type? { Bool.self }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let label = validatedProperties["label"] as? String ?? ""
        let initialExpanded = validatedProperties["isExpanded"] as? Bool
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["isExpanded": initialExpanded ?? false]
        }
        let expandedBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["isExpanded"] as? Bool ?? false },
            set: { newValue in
                state.wrappedValue[element.id] = ["isExpanded": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        return AnyView(
            SwiftUI.DisclosureGroup(isExpanded: expandedBinding) {
                ForEach(element.children ?? [], id: \.id) { child in
                    ActionUIView(element: child, state: state, windowUUID: windowUUID)
                }
            } label: {
                Text(label)
            }
        )
    }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if let label = properties["label"] as? String {
            validatedProperties["label"] = label
        }
        if let children = properties["children"] as? [[String: Any]] {
            validatedProperties["children"] = children
        } else {
            print("Warning: DisclosureGroup requires 'children'; defaulting to empty array")
            validatedProperties["children"] = []
        }
        if let isExpanded = properties["isExpanded"] as? Bool {
            validatedProperties["isExpanded"] = isExpanded
        }
        
        return validatedProperties
    }    
}
