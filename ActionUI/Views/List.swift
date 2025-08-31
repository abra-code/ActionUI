/*
 Sample JSON for List view:
 {
   "type": "List",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "itemType": { "viewType": "Text" }, // Required: { "viewType": "Text"|"Button"|"Image"|"AsyncImage", "dataInterpretation": "path"|"systemName"|"assetName"|"mixed" (for Image/AsyncImage), "actionContext": "title"|"rowIndex" (for Button) }
     "items": ["Item1", "Item2"], // Required: Array of strings or string arrays
     "actionID": "list.action", // Optional: For Button viewType
     "doubleClickActionID": "list.doubleClick" // Optional: String for double-click action (macOS only)
   }
 }
   // Note: The List shows a single-column list of homogeneous views (Text, Button, Image, AsyncImage) specified by itemType.viewType. Selection is stored as [String] in state, using the item string or id. On macOS, double-click triggers doubleClickActionID with context (title or rowIndex). Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large lists (e.g., 10,000 items). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.
 */

import SwiftUI

struct List: ActionUIViewConstruction {
    static let valueType: Any.Type = [String].self // Value is the selected item as [String]
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        var itemType = properties["itemType"] as? [String: Any] ?? ["viewType": "Text"]
        let viewType = itemType["viewType"] as? String ?? "Text"
        if !["Text", "Button", "Image", "AsyncImage"].contains(viewType) {
            logger.log("List itemType.viewType must be 'Text', 'Button', 'Image', or 'AsyncImage'; defaulting to Text", .warning)
            itemType["viewType"] = "Text"
        }
        if viewType == "Image" || viewType == "AsyncImage" {
            let dataInterpretation = itemType["dataInterpretation"] as? String
            if !["path", "systemName", "assetName", "mixed"].contains(dataInterpretation) {
                logger.log("List itemType.dataInterpretation must be 'path', 'systemName', 'assetName', or 'mixed' for \(viewType); defaulting to systemName", .warning)
                itemType["dataInterpretation"] = "systemName"
            }
        }
        if viewType == "Button" {
            let actionContext = itemType["actionContext"] as? String
            if !["title", "rowIndex"].contains(actionContext) {
                logger.log("List itemType.actionContext must be 'title' or 'rowIndex' for Button; defaulting to title", .warning)
                itemType["actionContext"] = "title"
            }
        }
        validatedProperties["itemType"] = itemType
        
        if validatedProperties["items"] == nil {
            validatedProperties["items"] = []
        } else if let items = validatedProperties["items"] as? [String] {
            validatedProperties["items"] = items.map { [$0] }
        } else if !(validatedProperties["items"] is [[String]]) {
            logger.log("List items must be an array of strings or string arrays; defaulting to []", .warning)
            validatedProperties["items"] = []
        }

        if let doubleClickActionID = properties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if properties["doubleClickActionID"] != nil {
            logger.log("List doubleClickActionID must be a string; ignoring", .warning)
            validatedProperties["doubleClickActionID"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let itemType = properties["itemType"] as? [String: Any] ?? ["viewType": "Text"]
        let viewType = itemType["viewType"] as? String ?? "Text"
        let dataInterpretation = itemType["dataInterpretation"] as? String ?? "systemName"
        let actionContext = itemType["actionContext"] as? String ?? "title"
        let items: [[String]] = (properties["items"] as? [[String]]) ?? []
        let displayItems: [String] = items.map { $0.first ?? "" }.filter { !$0.isEmpty } // Display first column only
        let actionID = properties["actionID"] as? String
        let doubleClickActionID = properties["doubleClickActionID"] as? String
        
        // Append List-specific state only if not already set
        var mutated = false
        if model.value == nil {
            model.value = [] as [String]
            mutated = true
        }
        if model.states["content"] == nil {
            model.states["content"] = items
            mutated = true
        }
        if mutated {
        }
        
        let selectionBinding = Binding<String?>(
            get: {
                let value = model.value as? [String]
                return value?.first
            },
            set: { newValue in
                if let newValue = newValue,
                   let content = model.states["content"] as? [[String]],
                   let selectedRow = content.first(where: { $0.first == newValue }) {
                    model.value = selectedRow
                } else {
                    model.value = [] as [String]
                }
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        return SwiftUI.List(selection: selectionBinding) {
            SwiftUI.ForEach(displayItems.indices, id: \.self) { index in
                SwiftUI.Group {
                    let item = displayItems[index]
                    switch viewType {
                    case "Text":
                        SwiftUI.Text(item)
                    case "Button":
                        SwiftUI.Button(item) {
                            if let actionID = actionID {
                                let context: Any = actionContext == "rowIndex" ? index : item
                                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: context)
                            }
                        }
                    case "Image":
                        SwiftUI.Image(from: item, interpretation: dataInterpretation)
                    case "AsyncImage":
                        SwiftUI.AsyncImage(url: URL(string: item)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            SwiftUI.ProgressView()
                        }
                    default:
                        SwiftUI.Text(item)
                    }
                }
            }
        }
        .onChange(of: properties["items"] as? [[String]], initial: false) { oldItems, newItems in
            let newContent: [[String]] = newItems ?? []
            model.states["content"] = newContent
            if let selectedRow = model.value as? [String],
               !newContent.contains(where: { $0.first == selectedRow.first }) {
                model.value = [] as [String]
            }
            model.validatedProperties["items"] = newContent
        }
        #if canImport(AppKit)
        .onTapGesture(count: 2) {
            if let doubleClickActionID = doubleClickActionID,
               let selectedRow = model.value as? [String],
               !selectedRow.isEmpty,
               let index = displayItems.firstIndex(of: selectedRow.first ?? "") {
                let context: Any = actionContext == "rowIndex" ? index : selectedRow[0]
                ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: context)
            }
        }
        #endif
    }
}
