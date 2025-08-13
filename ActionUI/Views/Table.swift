/*
 Sample JSON for Table view (macOS only):
 {
   "type": "Table",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "columns": ["Name", "Age"],           // Required: Array of strings for column headers
     "rows": [["Alice", "30", "ID1"], ["Bob", "25", "ID2"]], // Optional: Array of string arrays, defaults to []. Extra columns preserved in content.
     "widths": [100, 50],                 // Optional: Array of integers for column widths
     "doubleClickActionID": "table.doubleClick" // Optional: String for double-click action identifier
   }
   // Note: The Table view is macOS-only, showing a multi-column table with string values. Selection is stored as [String] in state["value"], using row IDs for tracking. Rows are padded with empty strings if shorter than columns. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. The buildView closure is simplified using helper functions for state initialization, selection binding, table construction, and column creation. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts with ActionUI types. The buildTableView function returns SwiftUI.Table directly, using implicit @SwiftUI.TableColumnBuilder in the Table closure to ensure type checker compatibility.
 }
*/

import SwiftUI

struct Table: ActionUIViewConstruction {
    static let valueType: Any.Type = [String].self // Value is the selected row as [String]
    
    // Validates properties specific to Table; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if validatedProperties["columns"] == nil {
            validatedProperties["columns"] = []
        } else if !(validatedProperties["columns"] is [String]) {
            print("Warning: Table columns must be an array of strings; defaulting to []")
            validatedProperties["columns"] = []
        }
        if validatedProperties["rows"] == nil {
            validatedProperties["rows"] = []
        } else if !(validatedProperties["rows"] is [[String]]) {
            print("Warning: Table rows must be an array of string arrays; defaulting to []")
            validatedProperties["rows"] = []
        }
        if let rows = validatedProperties["rows"] as? [[String]],
           let columns = validatedProperties["columns"] as? [String] {
            validatedProperties["rows"] = rows.map { row in
                if row.count < columns.count {
                    print("Warning: Table row has \(row.count) values, expected at least \(columns.count); padding with empty strings")
                    return row + Array(repeating: "", count: columns.count - row.count)
                }
                return row
            }
        }
        if validatedProperties["widths"] == nil {
            validatedProperties["widths"] = []
        } else if !(validatedProperties["widths"] is [Int]) {
            print("Warning: Table widths must be an array of integers; defaulting to []")
            validatedProperties["widths"] = []
        }
        if let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if validatedProperties["doubleClickActionID"] != nil {
            print("Warning: Table doubleClickActionID must be a string; ignoring")
            validatedProperties["doubleClickActionID"] = nil
        }
        
        return validatedProperties
    }
    
    // Helper function to initialize state
    private static func initializeState(element: any ActionUIElement, state: Binding<[Int: Any]>, rows: [[String]]) {
        let newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        var viewSpecificState: [String: Any] = [:]
        if newState["content"] == nil {
            viewSpecificState["content"] = rows
        }
        if newState["selectedRowID"] == nil {
            viewSpecificState["selectedRowID"] = nil as String?
        }
        if newState["value"] == nil {
            viewSpecificState["value"] = [] as [String]
        }
        if !viewSpecificState.isEmpty {
            state.wrappedValue[element.id] = newState.merging(viewSpecificState, uniquingKeysWith: { _, new in new })
        }
    }
    
    // Helper function to create selection binding
    private static func makeSelectionBinding(element: any ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, properties: [String: Any], rows: [TableRow]) -> Binding<String?> {
        Binding<String?>(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["selectedRowID"] as? String },
            set: { newValue in
                var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["selectedRowID"] = newValue
                if let selectedRowID = newValue,
                   let selectedRow = rows.first(where: { $0.id == selectedRowID }) {
                    newState["value"] = selectedRow.values
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
    }
    
    // Helper function to create a single TableColumn
    private static func makeColumn(index: Int, column: String, width: CGFloat?) -> SwiftUI.TableColumn<TableRow, Never, SwiftUI.Text, SwiftUI.Text> {
        SwiftUI.TableColumn(column) { row in
            SwiftUI.Text(row.values[index])
        }
        .width(width)
    }
    
    // Helper function to build the Table view
    private static func buildTableView(columns: [String], widths: [Int], rows: [TableRow], selectionBinding: Binding<String?>) -> SwiftUI.Table<[TableRow], Never> {
        SwiftUI.Table(rows, selection: selectionBinding) {
            SwiftUI.ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                makeColumn(index: index, column: column, width: widths.count > index ? CGFloat(widths[index]) : nil)
            }
        }
    }
    
    // Helper function to handle rows change
    private static func handleRowsChange(newRows: [[String]]?, state: Binding<[Int: Any]>, element: any ActionUIElement, rows: [TableRow]) {
        var newState: [String: Any] = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
        let newContent: [[String]] = newRows ?? []
        newState["content"] = newContent
        if let selectedRowID = newState["selectedRowID"] as? String,
           !rows.contains(where: { $0.id == selectedRowID }) {
            newState["selectedRowID"] = nil
            newState["value"] = [] as [String]
        }
        if var validatedProperties = newState["validatedProperties"] as? [String: Any] {
            validatedProperties["rows"] = newContent
            newState["validatedProperties"] = validatedProperties
        }
        state.wrappedValue[element.id] = newState
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { (element: any ActionUIElement, state: Binding<[Int: Any]>, windowUUID: String, properties: [String: Any]) -> any SwiftUI.View in
        #if os(macOS)
        let columns: [String] = (properties["columns"] as? [String]) ?? []
        let widths: [Int] = (properties["widths"] as? [Int]) ?? []
        let rows: [TableRow] = ((properties["rows"] as? [[String]]) ?? []).map { TableRow(id: UUID().uuidString, values: $0) }
        let doubleClickActionID: String? = properties["doubleClickActionID"] as? String
        
        initializeState(element: element, state: state, rows: properties["rows"] as? [[String]] ?? [])
        let selectionBinding = makeSelectionBinding(element: element, state: state, windowUUID: windowUUID, properties: properties, rows: rows)
        
        return buildTableView(columns: columns, widths: widths, rows: rows, selectionBinding: selectionBinding)
            .onChange(of: properties["rows"] as? [[String]]) { newRows in
                handleRowsChange(newRows: newRows, state: state, element: element, rows: rows)
            }
            .onTapGesture(count: 2) {
                if let doubleClickActionID = doubleClickActionID,
                   let selectedRow = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? [String],
                   !selectedRow.isEmpty {
                    Task { @MainActor in
                        ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                    }
                }
            }
        #else
        return SwiftUI.EmptyView()
        #endif
    }
}

struct TableRow: Identifiable {
    let id: String
    let values: [String]
}
