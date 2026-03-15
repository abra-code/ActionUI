// Sources/Views/Table.swift
/*
 Sample JSON for Table view (macOS only):
 {
   "type": "Table",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "columns": ["Name", "Action", "Icon"], // Required: Array of strings for column headers
     "columnTypes": [                       // Optional: Per-column type config array. Defaults to all Text.
       { "viewType": "Text" },              // Each entry: { "viewType": "Text"|"Button"|"Image"|"AsyncImage"
       { "viewType": "Button",              // Columns without an entry default to Text.
         "actionContext": "rowIndex",       // "actionContext": "title"|"rowIndex"|"columnIndex"|"rowColumnIndex" (Button only)
         "actionID": "row.action" },        // "actionID": "..." (Button only — fires on button click) }
       { "viewType": "Image",
         "dataInterpretation": "systemName" } // "dataInterpretation": "path"|"systemName"|"assetName"|"resourceName"|"mixed" (Image only)
     ],
     "widths": [100, 80, 40],               // Optional: Array of integers for ideal column widths (resizable; last column fills remaining space)
     "actionID": "table.selection.changed", // Optional: Fires on selection change (all cell types)
     "doubleClickActionID": "table.double.click" // Optional: String for double-click action (context = row index)
   }
 }
   // Note: The Table view is macOS-only, showing a multi-column table with per-column cell types specified by the columnTypes array. If columnTypes is omitted or shorter than columns, missing entries default to Text. Selection is stored as [String] in state["value"], using row IDs for tracking. The table-level actionID fires on selection change. Button columns have their own actionID in their columnTypes entry, fired on click — this cleanly separates selection events from button click events. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts. Uses TableColumnForEach for dynamic columns on macOS 14.4+. Falls back to a placeholder message for earlier versions.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large tables (e.g., 1000 rows x 50 columns). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.

 Observable state:
   value ([String])                    Selected row as an array of column strings (first column = display value).
                                       Access via getElementValue / setElementValue.
   states["content"]   [[String]]      All table rows; each inner array holds one row's column values.
                                       Access via getElementRows / setElementRows / appendElementRows /
                                       clearElementRows / getElementColumnCount.
   states["selectedRowID"] String?     Stable row ID of the currently selected row; nil when nothing is
                                       selected. No dedicated public API — use getElementState / setElementState.
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

struct Table: ActionUIViewConstruction {
    static let valueType: Any.Type = [String].self // Value is the selected row as [String]
    
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
            if !["Text", "Button", "Image", "AsyncImage"].contains(vt) {
                logger.log("Table columnTypes[\(i)].viewType must be 'Text', 'Button', 'Image', or 'AsyncImage'; defaulting to Text", .warning)
                ct["viewType"] = "Text"
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
            states["selectedRowID"] = nil
        }
        return states
    }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        #if canImport(AppKit)
        let columnTypes = properties["columnTypes"] as? [[String: Any]] ?? []
        let columns = (properties["columns"] as? [String]) ?? []
        let rows = (model.states["content"] as? [[String]]) ?? []
        let idealWidths = (properties["widths"] as? [Int])?.map { CGFloat($0) }
        let lastVisibleIndex = columns.count - 1

        let columnData = columns.enumerated().map { (index, name) in
            let ideal: CGFloat? = idealWidths.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? 100
            let isLast = (index == lastVisibleIndex)
            return ColumnData(
                id: index,
                name: name,
                minWidth: 40,
                idealWidth: ideal,
                maxWidth: isLast ? .infinity : nil
            )
        }
        let rowData = rows.enumerated().map { (index, row) in
            TableRowData(id: "row-\(index)", values: row)
        }
        
        let selectionBinding = Binding<Set<String>>(
            get: {
                guard let selectedRow = model.value as? [String],
                      !selectedRow.isEmpty else {
                    return Set<String>()
                }
                // Find which row-id corresponds to this value array
                if let matchingRow = rowData.first(where: { $0.values == selectedRow }) {
                    return Set([matchingRow.id])
                }
                return Set<String>()
            },
            set: { newSet in
                let newRowID: String? = newSet.first   // enforce single for now
        
                var selectedRowValues: [String] = []
        
                if let rowID = newRowID,
                   let selectedRow = rowData.first(where: { $0.id == rowID }) {
                    selectedRowValues = selectedRow.values
                }
        
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
        
        return SwiftUI.Table(rowData, selection: selectionBinding) {
            SwiftUI.TableColumnForEach(columnData) { column in
                SwiftUI.TableColumn(column.name) { row in
                    let value = column.id < row.values.count ? row.values[column.id] : ""
                    let colType = column.id < columnTypes.count ? columnTypes[column.id] : ["viewType": "Text"]
                    let viewType = colType["viewType"] as? String ?? "Text"
                    let dataInterpretation = colType["dataInterpretation"] as? String ?? "systemName"
                    let actionContext = colType["actionContext"] as? String ?? "title"
                    SwiftUI.Group {
                        switch viewType {
                        case "Text":
                            SwiftUI.Text(value)
                        case "Button":
                            SwiftUI.Button(value) {
                                if let buttonActionID = colType["actionID"] as? String {
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
                            }
                        case "Image":
                            SwiftUI.Image(from: value, interpretation: dataInterpretation)
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
        .onTapGesture(count: 2) {
            if let doubleClickActionID = properties["doubleClickActionID"] as? String,
               let selectedRow = model.value as? [String],
               !selectedRow.isEmpty,
               let index = rowData.firstIndex(where: { $0.values == selectedRow }) {
                ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: index)
            }
        }
        #else
        return SwiftUI.EmptyView()
        #endif
    }
    
    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? [String] {
            return initialValue
        }
        return [] as [String]
    }
}
