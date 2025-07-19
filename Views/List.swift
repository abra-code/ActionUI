/*
 Sample JSON for List:
 {
   "type": "List",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "items": ["Item1", "Item2"], // Optional: Array of strings, defaults to []
     "doubleClickActionID": "list.doubleClick", // Optional: String for double-click action (macOS only)
   }
   // Note: These properties are specific to List. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct List: ActionUIViewElement {
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
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let items = (validatedProperties["items"] as? [String]) ?? []
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = ["value": ""]
        }
        let selectionBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String ?? "" },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue]
                if let actionID = validatedProperties["actionID"] as? String {
                    actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                }
            }
        )
        
        return AnyView(
            SwiftUI.List(items, id: \.self, selection: selectionBinding) { item in
                SwiftUI.Text(item)
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        #if os(macOS)
        if let doubleClickActionID = properties["doubleClickActionID"] as? String {
            modifiedView = AnyView(modifiedView.onTapGesture(count: 2) {
                actionHandler(doubleClickActionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
            })
        }
        #endif
        return modifiedView
    }
}
