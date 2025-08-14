/*
 Sample JSON for Table view (macOS only):
 {
   "type": "Table",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "columns": ["Name", "Age"],           // Required: Array of strings for column headers; max 10, truncated if more
     "rows": [["Alice", "30", "ID1"], ["Bob", "25", "ID2"]], // Optional: Array of string arrays, defaults to []. Extra columns preserved in content.
     "widths": [100, 50],                 // Optional: Array of integers for column widths; max 10
     "doubleClickActionID": "table.doubleClick" // Optional: String for double-click action identifier
   }
   // Note: The Table view is macOS-only, showing a multi-column table with string values. Selection is stored as [String] in state["value"], using row IDs for tracking. Rows are padded with empty strings if shorter than columns. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties). The applyModifiers implementation is provided by the ActionUIViewConstruction protocol extension. The buildView closure is simplified using helper functions for state initialization, selection binding, table construction, and column building. SwiftUI types are explicitly prefixed (e.g., SwiftUI.Table, SwiftUI.TableColumn) to avoid namespace conflicts. For dynamic columns on macOS 14.4+, uses chained if statements in @TableColumnBuilder<TableRow, Never> (up to 10 columns) leveraging Optional conformance; requires macOS 14.4+ for conditional conformance. For earlier versions, falls back to a placeholder message.
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
        let maxColumns = 10
        if let columns = validatedProperties["columns"] as? [String], columns.count > maxColumns {
            print("Warning: Table supports up to \(maxColumns) columns due to builder limits; truncating to first \(maxColumns)")
            validatedProperties["columns"] = Array(columns[0..<maxColumns])
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
        if let widths = validatedProperties["widths"] as? [Int], widths.count > maxColumns {
            print("Warning: Table widths truncated to first \(maxColumns)")
            validatedProperties["widths"] = Array(widths[0..<maxColumns])
        }
        if let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if validatedProperties["doubleClickActionID"] != nil {
            print("Warning: Table doubleClickActionID must be a string; ignoring")
            validatedProperties["doubleClickActionID"] = nil
        }
        
        return validatedProperties
    }
    
#if os(macOS)
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
    @inline(__always)
    private static func makeColumn(index: Int, column: String, width: CGFloat?) -> some TableColumnContent<TableRow, Never> {
        SwiftUI.TableColumn(column) { row in
            SwiftUI.Text(row.values[index])
        }
        .width(width)
    }
    
    // Helper function to build columns dynamically using chained if statements (requires macOS 14.4+ for Optional conformance)
    @TableColumnBuilder<TableRow, Never>
    @available(macOS 14.4, *)
    private static func buildColumns(columns: [String], widths: [Int]) -> some TableColumnContent<TableRow, Never> {
        if columns.count > 0 {
            makeColumn(index: 0, column: columns[0], width: widths.count > 0 ? CGFloat(widths[0]) : nil)
        }
        if columns.count > 1 {
            makeColumn(index: 1, column: columns[1], width: widths.count > 1 ? CGFloat(widths[1]) : nil)
        }
        if columns.count > 2 {
            makeColumn(index: 2, column: columns[2], width: widths.count > 2 ? CGFloat(widths[2]) : nil)
        }
        if columns.count > 3 {
            makeColumn(index: 3, column: columns[3], width: widths.count > 3 ? CGFloat(widths[3]) : nil)
        }
        if columns.count > 4 {
            makeColumn(index: 4, column: columns[4], width: widths.count > 4 ? CGFloat(widths[4]) : nil)
        }
        if columns.count > 5 {
            makeColumn(index: 5, column: columns[5], width: widths.count > 5 ? CGFloat(widths[5]) : nil)
        }
        if columns.count > 6 {
            makeColumn(index: 6, column: columns[6], width: widths.count > 6 ? CGFloat(widths[6]) : nil)
        }
        if columns.count > 7 {
            makeColumn(index: 7, column: columns[7], width: widths.count > 7 ? CGFloat(widths[7]) : nil)
        }
        if columns.count > 8 {
            makeColumn(index: 8, column: columns[8], width: widths.count > 8 ? CGFloat(widths[8]) : nil)
        }
        if columns.count > 9 {
            makeColumn(index: 9, column: columns[9], width: widths.count > 9 ? CGFloat(widths[9]) : nil)
        }
    }
    
    // Helper function to build the Table view
    private static func buildTableView(columns: [String], widths: [Int], rows: [TableRow], selectionBinding: Binding<String?>) -> any SwiftUI.View {
        if #available(macOS 14.4, *) {
            SwiftUI.Table(rows, selection: selectionBinding) {
                buildColumns(columns: columns, widths: widths)
            }
        } else {
            // Fallback for pre-macOS 14.4: Use a fixed number of columns or alternative view (e.g., List)
            // For simplicity, show a message or empty
            SwiftUI.Text("Table requires macOS 14.4 or later for dynamic columns")
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
#endif // os(macOS)
    
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
