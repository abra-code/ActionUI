// Sources/Views/Table.swift
/*
 Sample JSON for Table view (macOS only):
 {
   "type": "Table",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "columns": ["Name", "Action", "Icon"], // Required: Array of strings for column headers
     "columnHeadersVisibility": "hidden",   // Optional: column headers visibility: "automatic", "hidden", "visible"
     "columnTypes": [                       // Optional: Per-column type config array. Defaults to all Text.
       { "viewType": "Text" },              // Each entry: { "viewType": "Text"|"Button"|"Image"|"AsyncImage"|"Toggle"
       { "viewType": "Button",              // Columns without an entry default to Text.
         "actionContext": "rowIndex",       // "actionContext": "title"|"rowIndex"|"columnIndex"|"rowColumnIndex" (Button only)
         "actionID": "row.action" },        // "actionID": "..." (Button only — fires on button click) }
       { "viewType": "Image",
         "dataInterpretation": "systemName" }, // "dataInterpretation": "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image & Button)
       { "viewType": "Toggle",              // A checkbox per row. The cell text is its state: "true" or "1" is on, "false", "0" or empty is off (any letter case).
         "style": "checkbox",               // "style": "checkbox" (default)|"switch"|"button" (Toggle only)
         "actionID": "row.toggled",         // "actionID": "..." (Toggle only - fires on a user toggle, after the cell is written; viewPartID = column index, context = row index)
         "disabledColumn": 4 }              // "disabledColumn": 1-based column number (hidden columns included) whose text, read the same way, disables the cell for that row (Toggle only)
     ],
     "widths": [100, 80, 40],               // Optional: Array of integers for ideal column widths (resizable; last column fills remaining space)
     "minWidths": [80, 60, 30],             // Optional: Array of integers for minimum column widths in points; columns cannot be resized below these. Missing entries default to 10.
     "actionID": "table.selection.changed", // Optional: Fires on selection change (all cell types)
     "doubleClickActionID": "table.double.click" // Optional: String for double-click action (context = row index)
   }
 }
   // Note: The Table view is macOS-only, showing a multi-column table with per-column cell types specified by the columnTypes array. If columnTypes is omitted or shorter than columns, missing entries default to Text. Selection is stored as [String] in state["value"] (the selected row's columns) and highlights the row with those columns. A rows change keeps the selection on its row (an equal row, else the row with the same first column, the same one among several, with its new columns), or clears it; no actionID fires. The table-level actionID fires on every selection change the user makes, a deselect included. Button columns have their own actionID in their columnTypes entry, fired on click — this cleanly separates selection events from button click events. A Toggle column shows a checkbox with no title (the column header names it); a user toggle writes "true" or "false" into that cell of states["content"], keeps the selection where it was, and then fires the entry's actionID with viewPartID = the column index and context = the row index, so a handler reads the new state from the rows. Toggling does not select the row and does not fire the table-level actionID; a rows change made by the host fires nothing. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts. Uses TableColumnForEach for dynamic columns.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large tables (e.g., 1000 rows x 50 columns). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.

 Observable state:
   value ([String])                    Selected row as an array of column strings (first column = display value).
                                       Access via getElementValue / setElementValue. Select a row
                                       programmatically (without replacing rows, firing no actionID) via
                                       selectElementRow(index:), selectElementRow(matching:column:), or
                                       clearElementSelection.
   states["content"]   [[String]]      All table rows; each inner array holds one row's column values.
                                       Access via getElementRows / setElementRows / appendElementRows /
                                       clearElementRows / getElementColumnCount.
 */

import SwiftUI

struct TableRowData: Identifiable {
    let id: String
    let values: [String]
}

struct ColumnData: Identifiable {
    let id: Int
    let name: String
    let minWidth: CGFloat?
    let idealWidth: CGFloat?
    let maxWidth: CGFloat?
}

/// A Toggle cell of a Table column: a checkbox (or switch, or button) with no title, showing
/// the cell's row data. A user toggle is handed to `onToggle` after the view update; the
/// table then redraws from the row written.
struct TableToggleCell: SwiftUI.View {
    let isOn: Bool
    let style: String
    let isDisabled: Bool
    let onToggle: @MainActor (Bool) -> Void

    var body: some SwiftUI.View {
        let binding = mainActorBinding(
            get: { isOn },
            set: { newValue in
                guard newValue != isOn else { return }
                DispatchQueue.main.async { onToggle(newValue) }
            }
        )
        styled(SwiftUI.Toggle("", isOn: binding).labelsHidden())
            .disabled(isDisabled)
    }

    @ViewBuilder
    private func styled(_ toggle: some SwiftUI.View) -> some SwiftUI.View {
        switch style {
        case "switch":
            toggle.toggleStyle(SwitchToggleStyle())
        case "button":
            toggle.toggleStyle(ButtonToggleStyle())
        default:
            #if os(macOS)
            toggle.toggleStyle(CheckboxToggleStyle())
            #else
            toggle.toggleStyle(SwitchToggleStyle())
            #endif
        }
    }
}

struct Table: ActionUIViewConstruction {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = [String].self // Value is the selected row as [String]
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        // Parse columnTypes array — each entry: { viewType, dataInterpretation?, actionContext?, actionID? }
        var columnTypes = properties["columnTypes"] as? [[String: Any]] ?? []
        let columns = properties["columns"] as? [String] ?? []
        // Pad to match columns count, defaulting to Text
        while columnTypes.count < columns.count {
            columnTypes.append(["viewType": "Text"])
        }
        // Validate each entry
        for i in 0..<columnTypes.count {
            var ct = columnTypes[i]
            let vt = ct["viewType"] as? String ?? "Text"
            if !["Text", "Button", "Image", "AsyncImage", "Toggle"].contains(vt) {
                logger.log("Table columnTypes[\(i)].viewType must be 'Text', 'Button', 'Image', 'AsyncImage', or 'Toggle'; defaulting to Text", .warning)
                ct["viewType"] = "Text"
            }
            if vt == "Toggle" {
                if let style = ct["style"], !["checkbox", "switch", "button"].contains(style as? String) {
                    logger.log("Table columnTypes[\(i)].style must be 'checkbox', 'switch', or 'button' for Toggle; defaulting to checkbox", .warning)
                    ct.removeValue(forKey: "style")
                }
                if let disabledColumn = ct["disabledColumn"], (disabledColumn as? Int ?? 0) < 1 {
                    logger.log("Table columnTypes[\(i)].disabledColumn must be a 1-based column number for Toggle; ignoring", .warning)
                    ct.removeValue(forKey: "disabledColumn")
                }
            }
            if vt == "Image" {
                let di = ct["dataInterpretation"] as? String
                if !["path", "systemName", "assetName", "resourceName", "mixed"].contains(di) {
                    logger.log("Table columnTypes[\(i)].dataInterpretation must be 'path', 'systemName', 'assetName', 'resourceName', or 'mixed' for Image; defaulting to systemName", .warning)
                    ct["dataInterpretation"] = "systemName"
                }
            }
            if vt == "Button" {
                let ac = ct["actionContext"] as? String
                if !["title", "rowIndex", "columnIndex", "rowColumnIndex"].contains(ac) {
                    logger.log("Table columnTypes[\(i)].actionContext must be 'title', 'rowIndex', 'columnIndex', or 'rowColumnIndex' for Button; defaulting to title", .warning)
                    ct["actionContext"] = "title"
                }
                // Optional dataInterpretation for image-only buttons
                if let di = ct["dataInterpretation"] as? String,
                   !["path", "systemName", "assetName", "resourceName", "mixed"].contains(di) {
                    logger.log("Table columnTypes[\(i)].dataInterpretation must be 'path', 'systemName', 'assetName', 'resourceName', or 'mixed' for Button; ignoring", .warning)
                    ct.removeValue(forKey: "dataInterpretation")
                }
            }
            columnTypes[i] = ct
        }
        validatedProperties["columnTypes"] = columnTypes
        
        if validatedProperties["columns"] == nil {
            validatedProperties["columns"] = []
        } else if !(validatedProperties["columns"] is [String]) {
            logger.log("Table columns must be an array of strings; defaulting to []", .warning)
            validatedProperties["columns"] = []
        }
        if let widths = properties["widths"] as? [Int] {
            validatedProperties["widths"] = widths
        } else if properties["widths"] != nil {
            logger.log("Table widths must be an array of integers; ignoring", .warning)
            validatedProperties["widths"] = nil
        }

        if let minWidths = properties["minWidths"] as? [Int] {
            validatedProperties["minWidths"] = minWidths
        } else if properties["minWidths"] != nil {
            logger.log("Table minWidths must be an array of integers; ignoring", .warning)
            validatedProperties["minWidths"] = nil
        }

        if let columnHeadersVisibility = properties["columnHeadersVisibility"] {
            if let str = columnHeadersVisibility as? String {
                let validValues = ["visible", "hidden", "automatic"]
                if !validValues.contains(str) {
                    logger.log("Invalid columnHeadersVisibility '\(str)'; expected one of \(validValues), ignoring", .warning)
                    validatedProperties["columnHeadersVisibility"] = nil
                }
            } else {
                logger.log("Invalid type for columnHeadersVisibility: expected String, got \(type(of: columnHeadersVisibility)), ignoring", .warning)
                validatedProperties["columnHeadersVisibility"] = nil
            }
        }

        if let doubleClickActionID = properties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if properties["doubleClickActionID"] != nil {
            logger.log("Table doubleClickActionID must be a string; ignoring", .warning)
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
        #if canImport(AppKit)
        let columnTypes = properties["columnTypes"] as? [[String: Any]] ?? []
        let columns = (properties["columns"] as? [String]) ?? []
        let rows = (model.states["content"] as? [[String]]) ?? []
        let idealWidths = (properties["widths"] as? [Int])?.map { CGFloat($0) }
        let minWidths = (properties["minWidths"] as? [Int])?.map { CGFloat($0) }
        let lastVisibleIndex = columns.count - 1

        var columnHeadersVisibility: SwiftUI.Visibility = .automatic
        if let columnHeadersVisibilityString = properties["columnHeadersVisibility"] as? String {
            if columnHeadersVisibilityString == "hidden" {
                columnHeadersVisibility = .hidden
            } else if columnHeadersVisibilityString == "visible" {
                columnHeadersVisibility = .visible
            }
        }

        // Find the column with the largest ideal width — it fills remaining space
        let resolvedWidths = columns.indices.map { index in
            idealWidths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? CGFloat(100)
        }
        let maxIdeal = resolvedWidths.max() ?? 100
        let columnData = columns.enumerated().map { (index, name) in
            let ideal = resolvedWidths[index]
            let isFillColumn = (ideal == maxIdeal)
            // Resolved minimum width: an explicit minWidths entry, else the legacy default of min(ideal, 10).
            let resolvedMin = minWidths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? Swift.min(ideal, 10)
            // Honor the minimum: ideal (and a non-fill column's max) can never fall below it,
            // keeping min <= ideal <= max as SwiftUI's .width(min:ideal:max:) requires.
            let clampedIdeal = Swift.max(ideal, resolvedMin)
            return ColumnData(
                id: index,
                name: name,
                minWidth: resolvedMin,
                idealWidth: clampedIdeal,
                maxWidth: isFillColumn ? .infinity : clampedIdeal
            )
        }
        
        let rowData = rows.enumerated().map { (index, row) in
            TableRowData(id: "row-\(index)", values: row)
        }
        
        let selectionBinding = makeSelectionBinding(
            rowData: rowData, model: model, actionID: properties["actionID"] as? String,
            windowUUID: windowUUID, viewID: element.id
        )

        return SwiftUI.Table(rowData, selection: selectionBinding) {
            SwiftUI.TableColumnForEach(columnData) { column in
                SwiftUI.TableColumn(column.name) { row in
                    let value = column.id < row.values.count ? row.values[column.id] : ""
                    let colType = column.id < columnTypes.count ? columnTypes[column.id] : ["viewType": "Text"]
                    let viewType = colType["viewType"] as? String ?? "Text"
                    let dataInterpretation = colType["dataInterpretation"] as? String
                    let actionContext = colType["actionContext"] as? String ?? "title"
                    // Extract the button actionID here: colType is a non-Sendable [String: Any] and
                    // must not be captured into the Button's main-actor action closure (Swift 6 sending rule).
                    let buttonActionID = colType["actionID"] as? String
                    let toggleStyle = colType["style"] as? String ?? "checkbox"
                    let disabledColumn = colType["disabledColumn"] as? Int
                    SwiftUI.Group {
                        switch viewType {
                        case "Toggle":
                            TableToggleCell(
                                isOn: TemplateHelper.rowBool(value) ?? false,
                                style: toggleStyle,
                                isDisabled: disabledColumn.map { $0 <= row.values.count && TemplateHelper.rowBool(row.values[$0 - 1]) == true } ?? false
                            ) { newValue in
                                Table.commitCellToggle(
                                    newValue, drawnRow: row.values,
                                    rowIndex: rowData.firstIndex(where: { $0.id == row.id }) ?? -1,
                                    column: column.id, actionID: buttonActionID,
                                    windowUUID: windowUUID, viewID: element.id
                                )
                            }
                        case "Text":
                            SwiftUI.Text(value)
                        case "Button":
                            SwiftUI.Button {
                                if let buttonActionID {
                                    let context: Any = {
                                        switch actionContext {
                                        case "rowIndex": return rowData.firstIndex(where: { $0.id == row.id }) ?? -1
                                        case "columnIndex": return column.id
                                        case "rowColumnIndex": return Point(row: rowData.firstIndex(where: { $0.id == row.id }) ?? -1, column: column.id)
                                        default: return value
                                        }
                                    }()
                                    ActionUIModel.shared.actionHandler(buttonActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: column.id, context: context)
                                }
                            } label: {
                                if let dataInterpretation {
                                    SwiftUI.Image(from: value, interpretation: dataInterpretation)
                                } else {
                                    SwiftUI.Text(value)
                                }
                            }
                        case "Image":
                            SwiftUI.Image(from: value, interpretation: dataInterpretation ?? "mixed")
                        case "AsyncImage":
                            SwiftUI.AsyncImage(url: URL(string: value)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                SwiftUI.ProgressView()
                            }
                        default:
                            SwiftUI.Text(value)
                        }
                    }
                }
                .width(min: column.minWidth, ideal: column.idealWidth, max: column.maxWidth)
            }
        }
        .tableColumnHeaders(columnHeadersVisibility)
        // Double-click handling. A plain .onTapGesture(count: 2) on a Table never
        // fires for row clicks on macOS — the rows consume the mouse events for
        // selection. The collection's own primaryAction is the supported double-click
        // (and Return-key) hook, so route doubleClickActionID through it instead.
        .contextMenu(forSelectionType: String.self) { _ in
            // No context-menu items: this modifier is used only for its primaryAction.
        } primaryAction: { ids in
            if let doubleClickActionID = properties["doubleClickActionID"] as? String,
               let firstID = ids.first,
               let index = rowData.firstIndex(where: { $0.id == firstID }) {
                // Keep selection/value in sync for env export, with the row as it is now.
                let current = model.states["content"] as? [[String]] ?? []
                model.value = ActionUIModel.reconciledSelection(rowData[index].values, from: rowData.map(\.values), to: current)
                ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: index)
            }
        }
        #else
        return SwiftUI.EmptyView()
        #endif
    }
    
    /// A user toggle of a Toggle cell: writes "true" or "false" into that cell of the rows
    /// (the selection follows its row), then fires the column's `actionID` with the column
    /// as `viewPartID` and the row index as context, the Button cell's "rowIndex" convention.
    /// Returns whether the toggle was taken (false when the row is gone).
    @discardableResult
    static func commitCellToggle(
        _ isOn: Bool,
        drawnRow: [String],
        rowIndex: Int,
        column: Int,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) -> Bool {
        guard let index = TemplateHelper.writeRowCell(
            windowUUID: windowUUID, containerID: viewID, drawnRow: drawnRow,
            rowIndex: rowIndex, column: column, text: TemplateHelper.rowBoolText(isOn)
        ) else { return false }
        if let actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: column, context: index)
        }
        return true
    }

    /// The Table's selection binding, by row id ("row-<index>") into `rowData`, the rows this
    /// render draws. The value is the selected row's columns (`[]` when nothing is selected);
    /// the user's changes, a deselect included, go through `SelectionListHelper.commitRowSelection`,
    /// which fires `actionID` and takes the row as it is in the current rows.
    static func makeSelectionBinding(
        rowData: [TableRowData],
        model: ViewModel,
        actionID: String?,
        windowUUID: String,
        viewID: Int
    ) -> Binding<Set<String>> {
        let drawnRows = rowData.map(\.values)
        return mainActorBinding(
            get: {
                guard let selectedRow = model.value as? [String],
                      !selectedRow.isEmpty,
                      let matchingRow = rowData.first(where: { $0.values == selectedRow }) else {
                    return Set<String>()
                }
                return Set([matchingRow.id])
            },
            set: { newSet in
                // Enforce single selection (take the first if several arrive).
                let clicked: [String]
                if let rowID = newSet.first {
                    guard let row = rowData.first(where: { $0.id == rowID }) else { return }
                    clicked = row.values
                } else {
                    clicked = []
                }
                SelectionListHelper.commitRowSelection(
                    clicked, drawnRows: drawnRows, model: model,
                    actionID: actionID, windowUUID: windowUUID, viewID: viewID
                )
            }
        )
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}
