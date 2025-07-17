/*
 Sample JSON for List:
 {
   "type": "List",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "items": ["Item1", "Item2"], // Optional: Array of strings, defaults to []
     "doubleClickActionID": "list.doubleClick", // Optional: String for double-click action (macOS only)
   }
   // Note: These properties are specific to List. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct List: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        validatedProperties["items"] = validatedProperties["items"] as? [String] ?? []
        
        if let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if validatedProperties["doubleClickActionID"] != nil {
            print("Warning: List doubleClickActionID must be a string; ignoring")
            validatedProperties["doubleClickActionID"] = nil
        }
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("List") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let items = (properties["items"] as? [String]) ?? []
            if state.wrappedValue[element.id] == nil {
                state.wrappedValue[element.id] = ["value": ""]
            }
            let selectionBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue ?? ""]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            var list = SwiftUI.List(items, id: \.self, selection: selectionBinding) { item in
                SwiftUI.Text(item)
            }
            .onChange(of: state.wrappedValue[element.id]?["value"]) { newValue in
                if let actionID = properties["actionID"] as? String, newValue != nil {
                    actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                }
            }
            #if os(macOS)
            list = list.onTapGesture(count: 2) {
                if let actionID = properties["doubleClickActionID"] as? String,
                   let selectedItem = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String {
                    actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                }
            }
            #endif
            return AnyView(list)
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers beyond base View properties
    }
}
