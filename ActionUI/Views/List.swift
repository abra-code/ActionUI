// Sources/Views/List.swift
/*
 Sample JSON for List view:
 {
   "type": "List",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "itemType": {                            // Optional: Defaults to { "viewType": "Text" }
       "viewType": "Button",                  // "Text"|"Button"|"Image"|"AsyncImage"
       "actionContext": "rowIndex",           // "title"|"rowIndex" (Button only)
       "actionID": "list.buttonClick",        // Button only — fires on button click
       "dataInterpretation": "systemName"     // "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image only)
     },
     "actionID": "list.selection.changed",    // Optional: Fires on selection change (all cell types)
     "doubleClickActionID": "list.double.click"  // Optional: String for double-click action (macOS only, context = row index)
   }
 }
   // Note: The List shows a single-column list of homogeneous views (Text, Button, Image, AsyncImage) specified by itemType.viewType. Selection is stored as [String] in state, using the item string or id. The list-level actionID fires on selection change. Button items have their own actionID in itemType, fired on click — this cleanly separates selection events from button click events. On macOS, double-click triggers doubleClickActionID with row index as context. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large lists (e.g., 10,000 items). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.

 Observable state:
   value ([String])                   Selected item as a one-element string array (or empty when nothing selected).
                                      Access via getElementValue / setElementValue.
   states["content"]  [[String]]      All list items; each inner array holds the item string and any optional
                                      hidden-column data. Access via getElementRows / setElementRows /
                                      appendElementRows / clearElementRows.
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
        if viewType == "Image" {
            let dataInterpretation = itemType["dataInterpretation"] as? String
            if !["path", "systemName", "assetName", "resourceName", "mixed"].contains(dataInterpretation) {
                logger.log("List itemType.dataInterpretation must be 'path', 'systemName', 'assetName', 'resourceName', or 'mixed' for \(viewType); defaulting to systemName", .warning)
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
        
        if let doubleClickActionID = properties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if properties["doubleClickActionID"] != nil {
            logger.log("List doubleClickActionID must be a string; ignoring", .warning)
            validatedProperties["doubleClickActionID"] = nil
        }
        
        return validatedProperties
    }
    
    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states: [String: Any] = model.states
        if states.isEmpty {
            states["content"] = [] as [[String]]
        }
        return states
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let itemType = properties["itemType"] as? [String: Any] ?? ["viewType": "Text"]
        let viewType = itemType["viewType"] as? String ?? "Text"
        let dataInterpretation = itemType["dataInterpretation"] as? String ?? "systemName"
        let actionContext = itemType["actionContext"] as? String ?? "title"
        let items: [[String]] = (model.states["content"] as? [[String]]) ?? []
        let displayItems: [String] = items.map { $0.first ?? "" }.filter { !$0.isEmpty } // Display first column only
        let buttonActionID = itemType["actionID"] as? String
        let doubleClickActionID = properties["doubleClickActionID"] as? String
        
        // Indices are 0..<displayItems.count — stable even with duplicate display strings
        let selectionBinding = Binding<Set<Int>>(
            get: {
                guard let selectedRow = model.value as? [String],
                      !selectedRow.isEmpty,
                      let content = model.states["content"] as? [[String]],
                      let selectedIndex = content.firstIndex(where: { $0 == selectedRow }) else {
                    return Set<Int>()
                }
                return Set([selectedIndex])
            },
            set: { newSet in
                // Enforce single selection for now (take first if somehow multi arrives)
                guard let newIndex = newSet.first else {
                    if !(model.value as? [String] ?? []).isEmpty {
                        DispatchQueue.main.async {
                            model.value = []
                            // optional: trigger valueChangeActionID if needed
                        }
                    }
                    return
                }

                guard let content = model.states["content"] as? [[String]],
                      content.indices.contains(newIndex) else { return }

                let selectedRowValues = content[newIndex]

                guard (model.value as? [String]) != selectedRowValues else { return }

                DispatchQueue.main.async {
                    model.value = selectedRowValues
                    if let actionID = properties["actionID"] as? String {
                        ActionUIModel.shared.actionHandler(
                            actionID,
                            windowUUID: windowUUID,
                            viewID: element.id,
                            viewPartID: 0
                        )
                    }
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
                            if let buttonActionID = buttonActionID {
                                let context: Any = actionContext == "rowIndex" ? index : item
                                ActionUIModel.shared.actionHandler(buttonActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: context)
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
        #if canImport(AppKit)
        .onTapGesture(count: 2) {
            if let doubleClickActionID = doubleClickActionID,
               let selectedRow = model.value as? [String],
               !selectedRow.isEmpty,
               let index = displayItems.firstIndex(of: selectedRow.first ?? "") {
                ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: index)
            }
        }
        #endif
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}
