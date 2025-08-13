/*
 Sample JSON for List view:
 {
   "type": "List",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "items": ["Item1", "Item2"], // Optional: Array of strings or array of string arrays, defaults to [], validated as [[String]]
     "doubleClickActionID": "list.doubleClick" // Optional: String for double-click action (macOS only)
   }
   // Note: The List shows a single-column list of strings, using the first element of each item if provided as string arrays. Selection is stored as [String] in state. On macOS, double-click triggers doubleClickActionID if a row is selected. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension.
 }
*/

import SwiftUI

struct List: ActionUIViewConstruction {
    static let valueType: Any.Type = [String].self // Value is the selected item as [String]
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
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
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { (element: any ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, properties: [String: Any]) -> any SwiftUI.View in
        let items: [[String]] = (properties["items"] as? [[String]]) ?? []
        let displayItems: [String] = items.map { $0.first ?? "" } // Display first column only
        
        // Append List-specific state only if not already set
        var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["content"] == nil {
            viewSpecificState["content"] = items
        }
        if newState["value"] == nil {
            viewSpecificState["value"] = [] as [String]
        }
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
        
        let selectionBinding = Binding<String?>(
            get: {
                let value = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? [String]
                return value?.first
            },
            set: { newValue in
                var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                if let newValue = newValue,
                   let content = newState["content"] as? [[String]],
                   let selectedRow = content.first(where: { $0.first == newValue }) {
                    newState["value"] = selectedRow
                } else {
                    newState["value"] = [] as [String]
                }
                state.wrappedValue[element.id] = newState
                if let actionID = properties["actionID"] as? String {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        let doubleClickActionID: String? = properties["doubleClickActionID"] as? String
        
        return SwiftUI.List(displayItems, id: \.self, selection: selectionBinding) { item in
            SwiftUI.Text(item)
        }
        .onChange(of: properties["items"] as? [[String]]) { newItems in
            var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
            let newContent: [[String]] = newItems ?? []
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
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        }
        #endif
    }
}
