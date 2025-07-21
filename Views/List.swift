/*
 Sample JSON for List view:
 {
   "type": "List",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "items": ["Item1", "Item2"], // Optional: Array of strings or array of string arrays, defaults to []
     "doubleClickActionID": "list.doubleClick" // Optional: String for double-click action (macOS only)
   }
   // Note: These properties are specific to List view. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct List: ActionUIViewElement {
    // Validates properties specific to List; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        if validatedProperties["items"] == nil {
            validatedProperties["items"] = []
        } else if let items = validatedProperties["items"] as? [String] {
            validatedProperties["items"] = items.map { [$0] }
        } else if !(validatedProperties["items"] is [[String]]) {
            print("Warning: List items must be an array of strings or array of string arrays; defaulting to []")
            validatedProperties["items"] = []
        }
        if let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if validatedProperties["doubleClickActionID"] != nil {
            print("Warning: List doubleClickActionID must be a string; ignoring")
            validatedProperties["doubleClickActionID"] = nil
        }
        
        return validatedProperties
    }
        
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let items = (validatedProperties["items"] as? [[String]]) ?? []
        let displayItems = items.map { $0.first ?? "" } // Display first column only
        
        // Initialize state if not present
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [
                "content": validatedProperties["items"] as? [[String]] ?? [],
                "value": [] as [String],
                "validatedProperties": validatedProperties
            ]
        }
        
        let selectionBinding = Binding<String?>(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? [String] }.map { $0.first ?? "" },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                if let newValue = newValue,
                   let content = newState["content"] as? [[String]],
                   let selectedRow = content.first(where: { $0.first == newValue }) {
                    newState["value"] = selectedRow
                } else {
                    newState["value"] = [] as [String]
                }
                state.wrappedValue[element.id] = newState
                if let actionID = validatedProperties["actionID"] as? String {
                    // Use singleton ActionUIModel.shared for action handling
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, controlPartID: 0)
                }
            }
        )
        
        let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String
        
        return AnyView(
            SwiftUI.List(displayItems, id: \.self, selection: selectionBinding) { item in
                SwiftUI.Text(item)
            }
            .onChange(of: validatedProperties["items"]) { newItems in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                let newContent = (newItems as? [[String]]) ?? (newItems as? [String])?.map { [$0] } ?? []
                newState["content"] = newContent
                if let selectedRow = newState["value"] as? [String],
                   !newContent.contains(where: { $0.first == selectedRow.first }) {
                    newState["value"] = [] as [String]
                }
                if var validatedProperties = newState["validatedProperties"] as? [String: Any] {
                    validatedProperties["items"] = newContent
                    newState["validatedProperties"] = validatedProperties
                }
                state.wrappedValue[element.id] = newState
            }
            #if os(macOS)
            .onTapGesture(count: 2) {
                if let doubleClickActionID = doubleClickActionID,
                   let selectedRow = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? [String],
                   !selectedRow.isEmpty {
                    // Use singleton ActionUIModel.shared for action handling
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, controlPartID: 0)
                }
            }
            #endif
        )
    }
        
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // No specific modifiers beyond base View properties
    }
}
