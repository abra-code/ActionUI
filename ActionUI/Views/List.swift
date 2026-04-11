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
      "doubleClickActionID": "list.double.click",  // Optional: String for double-click action (macOS only, context = row index)
      // List styling
      "listStyle": "plain",                   // Optional: list style — platform availability below
                                              //   "automatic"    — all platforms (system default)
                                              //   "plain"        — all platforms
                                              //   "inset"        — iOS, macOS, visionOS
                                              //   "sidebar"      — iOS, macOS, visionOS
                                              //   "grouped"      — iOS, tvOS, visionOS
                                              //   "insetGrouped" — iOS, visionOS only
      // Row styling — applied uniformly to all rows
      "listRowBackground": "blue",            // Optional: Color string (e.g., "blue", "#FF0000") — all platforms
      "listRowSeparator": "hidden",           // Optional: "visible"|"hidden"|"automatic" — iOS/macOS/visionOS only
      "listRowSeparatorTint": "gray",         // Optional: Color string for separator tint — iOS/macOS/visionOS only
      "listRowInsets": 16,                    // Optional: Number for uniform insets or {"top": 8, "leading": 16, "bottom": 8, "trailing": 16}
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
    //         Row styling (listRowBackground/listRowSeparator/listRowInsets) is applied via
    //         a rowModifier closure passed to SelectionListHelper.buildSelectableList.
    //
    //      b) Without actionID (no-selection mode): No selection binding. NavigationLinks handle
    //         their own taps. Action callbacks:
    //           - Button children: fire their own actionID on tap.
    //           - NavigationLink children: push destinations via NavigationStack.
    //           - Label/Text children: display-only; use Button if tap action is needed.
    //         Row styling properties are applied to each child view.
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
    //    Performance: Rows are identified by stable indices in ForEach, optimizing SwiftUI diffing for
    //    large lists (e.g., 10,000 items). When row styling properties (listRowBackground, listRowSeparator,
    //    listRowInsets) are set, rows are wrapped with AnyView to support modifier chaining. Without row
    //    styling, this is a no-op wrapper with negligible overhead. Image creation uses SwiftUI.Image
    //    extension, aligned with Image.swift. Ensure state updates are targeted to minimize re-renders.

  Observable state:
    value ([String])                   Selected item as a one-element string array (or empty when nothing selected).
                                       Access via getElementValue / setElementValue.
    states["content"]  [[String]]      All list items; each inner array holds the item string and any optional
                                       hidden-column data. Access via getElementRows / setElementRows /
                                       appendElementRows / clearElementRows.
*/

import SwiftUI

struct List: ActionUIViewConstruction {
    static var valueType: Any.Type = [String].self // Value is the selected item as [String]

    // MARK: - Row modifier helpers

    private static func hasRowModifiers(_ properties: [String: Any]) -> Bool {
        return properties["listRowBackground"] != nil ||
               properties["listRowSeparator"] != nil ||
               properties["listRowSeparatorTint"] != nil ||
               properties["listRowInsets"] != nil
    }

    /// Applies row-level list modifiers to a view. Returns the view wrapped in AnyView with any
    /// configured modifiers applied. When no row modifiers are set, returns AnyView(view) unchanged.
    private static func applyRowModifiers(_ view: some SwiftUI.View, properties: [String: Any]) -> AnyView {
        guard hasRowModifiers(properties) else { return AnyView(view) }
        var modified: any SwiftUI.View = view

        if let bgStr = properties["listRowBackground"] as? String,
           let color = ColorHelper.resolveColor(bgStr) {
            modified = modified.listRowBackground(color)
        }

        #if os(iOS) || os(macOS) || os(visionOS)
        if let sep = properties["listRowSeparator"] as? String {
            let visibility: Visibility
            switch sep {
            case "hidden":  visibility = .hidden
            case "visible": visibility = .visible
            default:        visibility = .automatic
            }
            modified = modified.listRowSeparator(visibility)
        }

        if let tintStr = properties["listRowSeparatorTint"] as? String,
           let color = ColorHelper.resolveColor(tintStr) {
            modified = modified.listRowSeparatorTint(color)
        }
        #endif

        if let insetsValue = properties["listRowInsets"] {
            let edgeInsets: EdgeInsets?
            if let n = insetsValue as? Double {
                let f = CGFloat(n)
                edgeInsets = EdgeInsets(top: f, leading: f, bottom: f, trailing: f)
            } else if let n = insetsValue as? Int {
                let f = CGFloat(n)
                edgeInsets = EdgeInsets(top: f, leading: f, bottom: f, trailing: f)
            } else if let dict = insetsValue as? [String: Any] {
                edgeInsets = EdgeInsets(
                    top: dict.cgFloat(forKey: "top") ?? 0,
                    leading: dict.cgFloat(forKey: "leading") ?? 0,
                    bottom: dict.cgFloat(forKey: "bottom") ?? 0,
                    trailing: dict.cgFloat(forKey: "trailing") ?? 0
                )
            } else {
                edgeInsets = nil
            }
            modified = modified.listRowInsets(edgeInsets)
        }

        return AnyView(modified)
    }

    /// Builds one row for homogeneous lists. Always returns AnyView so row modifiers can be uniformly
    /// applied regardless of the underlying view type (Text, Button, Image, AsyncImage).
    private static func buildHomogeneousRow(
        item: String, index: Int, viewType: String,
        dataInterpretation: String, buttonActionID: String?,
        actionContext: String, windowUUID: String, elementID: Int
    ) -> AnyView {
        let row: any SwiftUI.View
        switch viewType {
        case "Button":
            row = SwiftUI.Button(item) {
                if let aid = buttonActionID {
                    let ctx: Any = actionContext == "rowIndex" ? index : item
                    ActionUIModel.shared.actionHandler(aid, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: ctx)
                }
            }
        case "Image":
            row = SwiftUI.Image(from: item, interpretation: dataInterpretation)
        case "AsyncImage":
            row = SwiftUI.AsyncImage(url: URL(string: item)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                SwiftUI.ProgressView()
            }
        default: // "Text" and fallback
            row = SwiftUI.Text(item)
        }
        return AnyView(row)
    }

    // MARK: - Protocol conformance

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

        // Validate listStyle — allowed values are platform-specific
        if let style = properties["listStyle"] as? String {
            #if os(watchOS)
            let validListStyles = ["automatic", "plain"]
            #elseif os(tvOS)
            let validListStyles = ["automatic", "plain", "grouped"]
            #elseif os(macOS)
            let validListStyles = ["automatic", "plain", "inset", "sidebar"]
            #else // iOS, visionOS
            let validListStyles = ["automatic", "plain", "inset", "sidebar", "grouped", "insetGrouped"]
            #endif
            if !validListStyles.contains(style) {
                logger.log("List listStyle '\(style)' is not available on this platform; ignoring", .warning)
                validatedProperties["listStyle"] = nil
            }
        } else if properties["listStyle"] != nil {
            logger.log("List listStyle must be a String; ignoring", .warning)
            validatedProperties["listStyle"] = nil
        }

        // Validate listRowBackground — must be a color string
        if properties["listRowBackground"] != nil && !(properties["listRowBackground"] is String) {
            logger.log("List listRowBackground must be a color string; ignoring", .warning)
            validatedProperties["listRowBackground"] = nil
        }

        // Validate listRowSeparator
        if let sep = properties["listRowSeparator"] as? String {
            if !["visible", "hidden", "automatic"].contains(sep) {
                logger.log("List listRowSeparator must be 'visible', 'hidden', or 'automatic'; ignoring", .warning)
                validatedProperties["listRowSeparator"] = nil
            }
        } else if properties["listRowSeparator"] != nil {
            logger.log("List listRowSeparator must be a String; ignoring", .warning)
            validatedProperties["listRowSeparator"] = nil
        }

        // Validate listRowSeparatorTint — must be a color string
        if properties["listRowSeparatorTint"] != nil && !(properties["listRowSeparatorTint"] is String) {
            logger.log("List listRowSeparatorTint must be a color string; ignoring", .warning)
            validatedProperties["listRowSeparatorTint"] = nil
        }

        // Validate listRowInsets — must be a number or a dictionary with numeric edge keys
        if let insets = properties["listRowInsets"] {
            let isNumber = insets is Double || insets is Int
            let isDict = insets is [String: Any]
            if !isNumber && !isDict {
                logger.log("List listRowInsets must be a number or dictionary {top, leading, bottom, trailing}; ignoring", .warning)
                validatedProperties["listRowInsets"] = nil
            }
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
                let templateView = TemplateHelper.buildTemplateView(
                    template: template, row: rows[rowIndex], rowIndex: rowIndex,
                    parentID: parentID, windowUUID: windowUUID, logger: logger
                )
                return applyRowModifiers(templateView, properties: properties)
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
                    windowUUID: windowUUID,
                    rowModifier: hasRowModifiers(properties) ? { view in applyRowModifiers(view, properties: properties) } : nil
                )
            } else {
                // No-selection heterogeneous list mode: NavigationLinks handle their own taps.
                // No List(selection:) binding — on iOS, selection binding intercepts taps and
                // prevents NavigationLink from activating.
                // Row styling properties are applied to each child view.
                return SwiftUI.List {
                    ForEach(children, id: \.id) { child in
                        if let childModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[child.id] {
                            applyRowModifiers(
                                ActionUIView(element: child, model: childModel, windowUUID: windowUUID),
                                properties: properties
                            )
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
            let elementID = element.id

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
                                viewID: elementID,
                                viewPartID: 0
                            )
                        }
                    }
                }
            )

            return SwiftUI.List(selection: selectionBinding) {
                SwiftUI.ForEach(displayItems.indices, id: \.self) { index in
                    applyRowModifiers(
                        buildHomogeneousRow(
                            item: displayItems[index], index: index, viewType: viewType,
                            dataInterpretation: dataInterpretation, buttonActionID: buttonActionID,
                            actionContext: actionContext, windowUUID: windowUUID, elementID: elementID
                        ),
                        properties: properties
                    )
                }
            }
            #if canImport(AppKit)
            .onTapGesture(count: 2) {
                if let doubleClickActionID = doubleClickActionID,
                   let selectedRow = model.value as? [String],
                   !selectedRow.isEmpty,
                   let index = displayItems.firstIndex(of: selectedRow.first ?? "") {
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: elementID, viewPartID: 0, context: index)
                }
            }
            #endif
        }
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        if let style = properties["listStyle"] as? String {
            switch style {
            case "plain":
                modifiedView = modifiedView.listStyle(.plain)
            case "inset":
                #if os(iOS) || os(macOS) || os(visionOS)
                modifiedView = modifiedView.listStyle(.inset)
                #else
                logger.log("inset listStyle unavailable on this platform; ignoring", .warning)
                #endif
            case "sidebar":
                #if os(iOS) || os(macOS) || os(visionOS)
                modifiedView = modifiedView.listStyle(.sidebar)
                #else
                logger.log("sidebar listStyle unavailable on this platform; ignoring", .warning)
                #endif
            case "grouped":
                #if os(iOS) || os(tvOS) || os(visionOS)
                modifiedView = modifiedView.listStyle(.grouped)
                #else
                logger.log("grouped listStyle unavailable on this platform; ignoring", .warning)
                #endif
            case "insetGrouped":
                #if os(iOS) || os(visionOS)
                modifiedView = modifiedView.listStyle(.insetGrouped)
                #else
                logger.log("insetGrouped listStyle unavailable on this platform; ignoring", .warning)
                #endif
            default:
                break // "automatic" and unknown values use the system default
            }
        }
        return modifiedView
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}
