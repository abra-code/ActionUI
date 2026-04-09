// Sources/Views/List.swift
/*
  Sample JSON for List view:
  {
    "type": "List",
    "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
    "properties": {
      // Form 1: Homogeneous list of pre-declared types from external data
      "itemType": {                            // Optional: Defaults to { "viewType": "Text" }
        "viewType": "Button",                  // "Text"|"Button"|"Image"|"AsyncImage"
        "actionContext": "rowIndex",           // "title"|"rowIndex" (Button only)
        "actionID": "list.buttonClick",        // Button only — fires on button click
        "dataInterpretation": "systemName"     // "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image only)
      },
      "actionID": "list.selection.changed",    // Optional: Fires on selection change (all cell types)
      "doubleClickActionID": "list.double.click"  // Optional: String for double-click action (macOS only, context = row index)
    },
    // Form 2: Heterogeneous list from embedded JSON
    "children": [                            // Optional: Array of child views for complex lists
      { 
        "type": "NavigationLink", 
        "id": 10,                            // Recommended: Set unique ID for selection support
        "properties": { 
          "title": "Item 1" 
        },
        "destination": {                   // Destination must be a full view element
          "type": "Text",
          "properties": { "title": "Item 1 Detail" }
        }
      },
      { 
        "type": "Button", 
        "id": 11,                            // Recommended: Set unique ID for selection support
        "properties": { "title": "Item 2" } 
      }
    ],
    // Form 3: Data-driven list with template (replaces itemType with full ActionUI template)
    "template": {                           // "template" presence activates data-driven template mode; "id" required
      "type": "HStack",
      "children": [
        { "type": "Image", "properties": { "systemName": "$1" } }, // $1, $2, etc. are 1-based data column indexes
        { "type": "Text",  "properties": { "text": "$2" } }
      ]
    }
  }
    // Note: The List can operate in three modes (Form 1, 2, and 3):
    //   1. Homogeneous list: Shows a single-column list of homogeneous views (Text, Button, Image, AsyncImage) 
    //      specified by itemType.viewType. Selection is stored as [String] in state, using the item string or id. 
    //      The list-level actionID fires on selection change. Button items have their own actionID in itemType, 
    //      fired on click — this cleanly separates selection events from button click events. On macOS, 
    //      double-click triggers doubleClickActionID with row index as context.
    //   2. Heterogeneous list: Shows a list of arbitrary views defined in the "children" array.
    //      Operates in two sub-modes depending on whether actionID is set:
    //
    //      a) With actionID (selectable mode): List(selection:) binding is enabled using
    //         bidirectional child-ID mapping (same pattern as NavigationSplitView.buildSidebarList).
    //         Selection is stored in model.value as [String] with the stringified child element ID.
    //         actionID fires on selection change. Children should be Labels/Text (not NavigationLinks)
    //         because List(selection:) intercepts taps on iOS.
    //         When used inside NavigationStack with destinations, NavigationStack detects this pattern
    //         and handles push navigation — see NavigationStack.swift.
    //
    //      b) Without actionID (no-selection mode): No selection binding. NavigationLinks handle
    //         their own taps. Action callbacks:
    //           - Button children: fire their own actionID on tap.
    //           - NavigationLink children: push destinations via NavigationStack.
    //           - Label/Text children: display-only; use Button if tap action is needed.
    //
    //      Note: NavigationSplitView sidebar selection is handled by NavigationSplitView.buildSidebarList(),
    //      which constructs its own List(selection:) — it does not go through this List.buildView path.
    //      Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity,
    //      cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and
    //      applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
    //      The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension.
    //   3. Template-based list: homogeneous rows of ActionUI views based on pre-declared template
    //      Column text values are assigned to specific sub-view values by index
    //      Column indexes are 1-based: $1 (col 0), $2 (col 1), $N (col N-1), $0 (all)
    //      Data set via setElementRows/appendElementRows/clearElementRows.
    //      Selection and doubleClickActionID work the same as Form 1.
    //
    //    Performance: For homogeneous lists, child views are strongly typed to avoid AnyView overhead, 
    //    identified by stable indices in ForEach, optimizing SwiftUI diffing for large lists (e.g., 10,000 items). 
    //    For heterogeneous lists, views are constructed dynamically. Image creation uses SwiftUI.Image extension, 
    //    aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.

  Observable state:
    value ([String])                   Selected item as a one-element string array (or empty when nothing selected).
                                       Access via getElementValue / setElementValue.
    states["content"]  [[String]]      All list items; each inner array holds the item string and any optional
                                       hidden-column data. Access via getElementRows / setElementRows /
                                       appendElementRows / clearElementRows.
*/

import SwiftUI

struct List: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var valueType: Any.Type = [String].self // Value is the selected item as [String]
    
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
        // Template mode: render one template instance per row in states["content"].
        // Replaces itemType with full ActionUI template support for richer cell layouts.
        if let template = element.subviews?["template"] as? any ActionUIElementBase {
            let rows = (model.states["content"] as? [[String]]) ?? []
            let parentID = element.id
            let doubleClickActionID = properties["doubleClickActionID"] as? String
            let rowViews: [AnyView] = rows.indices.map { rowIndex in
                TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
            }

            // Selection binding: same index-based pattern as homogeneous list
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
                    guard let newIndex = newSet.first else {
                        if !(model.value as? [String] ?? []).isEmpty {
                            DispatchQueue.main.async { model.value = [] }
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
                                actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0
                            )
                        }
                    }
                }
            )

            return SwiftUI.List(selection: selectionBinding) {
                ForEach(rowViews.indices, id: \.self) { i in rowViews[i] }
            }
            #if canImport(AppKit)
            .onTapGesture(count: 2) {
                if let doubleClickActionID = doubleClickActionID,
                   let selectedRow = model.value as? [String],
                   !selectedRow.isEmpty,
                   let content = model.states["content"] as? [[String]],
                   let index = content.firstIndex(where: { $0 == selectedRow }) {
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: index)
                }
            }
            #endif
        }

        // Check for heterogeneous list (children array)
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        if !children.isEmpty {
            if let actionID = properties["actionID"] as? String {
                // Selectable heterogeneous list mode: List(selection:) with child ID mapping.
                // Same pattern as NavigationSplitView.buildSidebarList — Labels/Text are selectable,
                // actionID fires on selection change with child element ID as context.
                let windowModel = ActionUIModel.shared.windowModels[windowUUID]

                let selectionBinding = SelectionListHelper.makeHeterogeneousSelectionBinding(
                    model: model,
                    actionID: actionID,
                    windowUUID: windowUUID,
                    viewID: element.id
                )

                return SelectionListHelper.buildSelectableList(
                    selection: selectionBinding,
                    children: children,
                    listElement: element,
                    listModel: nil as ViewModel?,
                    windowModel: windowModel,
                    windowUUID: windowUUID
                )
            } else {
                // No-selection heterogeneous list mode: NavigationLinks handle their own taps.
                // No List(selection:) binding — on iOS, selection binding intercepts taps and
                // prevents NavigationLink from activating.
                return SwiftUI.List {
                    ForEach(children, id: \.id) { child in
                        if let childModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[child.id] {
                            ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                        }
                    }
                }
            }
        } else {
            // Homogeneous list mode
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
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}
