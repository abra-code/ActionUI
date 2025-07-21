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
   // Note: These properties are specific to Table view. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Table: ActionUIViewConstruction {
    // Validates properties specific to Table; baseline properties are validated by ActionUIRegistry.getValidatedProperties
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
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
        
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        #if os(macOS)
        let columns = (validatedProperties["columns"] as? [String]) ?? []
        let widths = (validatedProperties["widths"] as? [Int]) ?? []
        let rows = ((validatedProperties["rows"] as? [[String]]) ?? []).map { TableRow(id: UUID().uuidString, values: $0) }
        
        // Initialize state if not present
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [
                "content": validatedProperties["rows"] as? [[String]] ?? [],
                "selectedRowID": nil as String?,
                "value": [] as [String],
                "validatedProperties": validatedProperties
            ]
        }
        
        let selectionBinding = Binding<String?>(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["selectedRowID"] as? String },
            set: { newValue in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                newState["selectedRowID"] = newValue
                if let selectedRowID = newValue,
                   let content = newState["content"] as? [[String]],
                   let selectedRow = rows.first(where: { $0.id == selectedRowID }) {
                    newState["value"] = selectedRow.values
                } else {
                    newState["value"] = [] as [String]
                }
                state.wrappedValue[element.id] = newState
                if let actionID = validatedProperties["actionID"] as? String {
                    // Use singleton ActionUIModel.shared for action handling
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        
        let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String
        
        return AnyView(
            SwiftUI.Table(rows, selection: selectionBinding) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    SwiftUI.TableColumn(column, value: \.values[index]) { row in
                        SwiftUI.Text(row.values[index])
                    }
                    .width(widths.count > index ? CGFloat(widths[index]) : nil)
                }
            }
            .onChange(of: validatedProperties["rows"]) { newRows in
                var newState = (state.wrappedValue[element.id] as? [String: Any]) ?? [:]
                let newContent = newRows as? [[String]] ?? []
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
            .onTapGesture(count: 2) {
                if let doubleClickActionID = doubleClickActionID,
                   let selectedRowID = (state.wrappedValue[element.id] as? [String: Any])?["selectedRowID"] as? String,
                   let content = (state.wrappedValue[element.id] as? [String: Any])?["content"] as? [[String]] {
                    // Use singleton ActionUIModel.shared for action handling
                    ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
        )
        #else
        return AnyView(EmptyView())
        #endif
    }
        
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // No specific modifiers beyond base View properties
    }
}

struct TableRow: Identifiable {
    let id: String
    let values: [String]
}
