/*
 Sample JSON for Table view (macOS only):
 {
   "type": "Table",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction and diffing
   "properties": {
     "itemType": { "viewType": "Button", "actionContext": "rowColumnIndex" }, // Required, rowColumnIndex returns Point(row: Int, column: Int)
     "columns": ["Name", "Action"], // Required: Array of strings for column headers
     "rows": [["Alice", "Click"], ["Bob", "Edit"]], // Required: Array of string arrays
     "widths": [100, 80], // Optional: Array of integers for column widths
     "actionID": "table.action", // Optional: For Button viewType
     "doubleClickActionID": "table.doubleClick" // Optional: String for double-click action
   }
 }
   // Note: The Table view is macOS-only, showing a multi-column table with homogeneous views (Text, Button, Image, AsyncImage) specified by itemType.viewType. Selection is stored as [String] in state["value"], using row IDs for tracking. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts. Uses TableColumnForEach for dynamic columns on macOS 14.4+. Falls back to a placeholder message for earlier versions.
   // Performance: Child views are strongly typed to avoid AnyView overhead, identified by stable indices in ForEach, optimizing SwiftUI diffing for large tables (e.g., 1000 rows x 50 columns). Image creation uses SwiftUI.Image extension, aligned with Image.swift, to minimize overhead. Ensure state updates are targeted to minimize re-renders.
 */

import SwiftUI

struct TableRowData: Identifiable {
    let id: String
    let values: [String]
}

struct ColumnData: Identifiable {
    let id: Int
    let name: String
    let width: CGFloat
}

struct Table: ActionUIViewConstruction {
    static let valueType: Any.Type = [String].self // Value is the selected row as [String]
    
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validatedProperties = properties
        
        var itemType = properties["itemType"] as? [String: Any] ?? ["viewType": "Text"]
        let viewType = itemType["viewType"] as? String ?? "Text"
        if !["Text", "Button", "Image", "AsyncImage"].contains(viewType) {
            logger.log("Table itemType.viewType must be 'Text', 'Button', 'Image', or 'AsyncImage'; defaulting to Text", .warning)
            itemType["viewType"] = "Text"
        }
        if viewType == "Image" || viewType == "AsyncImage" {
            let dataInterpretation = itemType["dataInterpretation"] as? String
            if !["path", "systemName", "assetName", "mixed"].contains(dataInterpretation) {
                logger.log("Table itemType.dataInterpretation must be 'path', 'systemName', 'assetName', or 'mixed' for \(viewType); defaulting to systemName", .warning)
                itemType["dataInterpretation"] = "systemName"
            }
        }
        if viewType == "Button" {
            let actionContext = itemType["actionContext"] as? String
            if !["title", "rowIndex", "columnIndex", "rowColumnIndex"].contains(actionContext) {
                logger.log("Table itemType.actionContext must be 'title', 'rowIndex', 'columnIndex', or 'rowColumnIndex' for Button; defaulting to title", .warning)
                itemType["actionContext"] = "title"
            }
        }
        validatedProperties["itemType"] = itemType
        
        if validatedProperties["columns"] == nil {
            validatedProperties["columns"] = []
        } else if !(validatedProperties["columns"] is [String]) {
            logger.log("Table columns must be an array of strings; defaulting to []", .warning)
            validatedProperties["columns"] = []
        }
        if validatedProperties["rows"] == nil {
            validatedProperties["rows"] = []
        } else if !(validatedProperties["rows"] is [[String]]) {
            logger.log("Table rows must be an array of string arrays; defaulting to []", .warning)
            validatedProperties["rows"] = []
        }
        if let rows = validatedProperties["rows"] as? [[String]],
           let columns = validatedProperties["columns"] as? [String] {
            validatedProperties["rows"] = rows.map { row in
                if row.count < columns.count {
                    logger.log("Table row has \(row.count) values, expected at least \(columns.count); padding with empty strings", .warning)
                    return row + Array(repeating: "", count: columns.count - row.count)
                }
                return row
            }
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
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, state, windowUUID, properties, logger in
        #if canImport(AppKit)
        let itemType = properties["itemType"] as? [String: Any] ?? ["viewType": "Text"]
        let viewType = itemType["viewType"] as? String ?? "Text"
        let dataInterpretation = itemType["dataInterpretation"] as? String ?? "systemName"
        let actionContext = itemType["actionContext"] as? String ?? "title"
        let columns = (properties["columns"] as? [String]) ?? []
        let rows = (properties["rows"] as? [[String]]) ?? []
        let widths = (properties["widths"] as? [Int])?.map { CGFloat($0) } ?? Array(repeating: CGFloat(100), count: columns.count)
        
        let columnData = columns.enumerated().map { (index, name) in
            ColumnData(id: index, name: name, width: widths.indices.contains(index) ? widths[index] : 100)
        }
        let rowData = rows.enumerated().map { (index, row) in
            TableRowData(id: "row-\(index)", values: row)
        }
        
        // Append Table-specific state only if not already set
        var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var mutated = false
        if newState["content"] == nil {
            newState["content"] = rows
            mutated = true
        }
        if newState["selectedRowID"] == nil {
            newState["value"] = [] as [String]
            mutated = true
        }
        if mutated {
            state.wrappedValue[element.id] = newState
        }
        
        let selectionBinding = Binding<String?>(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["selectedRowID"] as? String },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["selectedRowID"] = newValue
                if let selectedRowID = newValue,
                   let selectedRow = rowData.first(where: { $0.id == selectedRowID }) {
                    newState["value"] = selectedRow.values
                } else {
                    newState["value"] = [] as [String]
                }
                state.wrappedValue[element.id] = newState
                if let valueChangeActionID = properties["valueChangeActionID"] as? String {
                    Task { @MainActor in
                    	ActionUIModel.shared.actionHandler(valueChangeActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        )
        
        return SwiftUI.Table(rowData, selection: selectionBinding) {
            SwiftUI.TableColumnForEach(columnData) { column in
                SwiftUI.TableColumn(column.name) { row in
                    let value = row.values[column.id]
                    SwiftUI.Group {
                        switch viewType {
                        case "Text":
                            SwiftUI.Text(value)
                        case "Button":
                            SwiftUI.Button(value) {
                                if let actionID = properties["actionID"] as? String {
                                    let context: Any = {
                                        switch actionContext {
                                        case "rowIndex": return rowData.firstIndex(where: { $0.id == row.id }) ?? -1
                                        case "columnIndex": return column.id
                                        case "rowColumnIndex": return Point(row: rowData.firstIndex(where: { $0.id == row.id }) ?? -1, column: column.id)
                                        default: return value
                                        }
                                    }()
                                    Task { @MainActor in
                                        ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: column.id, context: context)
                                    }
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
                .width(column.width)
            }
        }
        .onChange(of: properties["rows"] as? [[String]], initial: false) { oldRows, newRows in
            var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
            let newContent = newRows ?? []
            newState["content"] = newContent
            if let selectedRowID = newState["selectedRowID"] as? String,
               !rowData.contains(where: { $0.id == selectedRowID }) {
                newState["selectedRowID"] = nil
                newState["value"] = [] as [String]
            }
            if var validatedProperties = newState["validatedProperties"] as? [String: Any] {
                validatedProperties["rows"] = newContent
                newState["validatedProperties"] = validatedProperties
            }
            state.wrappedValue[element.id] = newState
        }
        .onTapGesture(count: 2) {
            if let doubleClickActionID = properties["doubleClickActionID"] as? String,
               let selectedRow = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? [String],
               !selectedRow.isEmpty,
               let index = rowData.firstIndex(where: { $0.values == selectedRow }) {
                let context: Any = actionContext == "rowIndex" ? index : selectedRow.first ?? ""
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: context)
                }
            }
        }
        #else
        return SwiftUI.EmptyView()
        #endif
    }
}
