/*
 Sample JSON for Table (macOS only):
 {
   "type": "Table",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "columns": ["Name", "Age"],           // Required: Array of strings for column headers
     "rows": [["Alice", "30"], ["Bob", "25"]], // Optional: Array of string arrays, defaults to []
     "widths": [100, 50],                 // Optional: Array of integers for column widths
     "doubleClickActionID": "table.doubleClick" // Optional: String for double-click action identifier
   }
   // Note: These properties are specific to Table. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Table: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = properties
        
        #if os(macOS)
        if validatedProperties["columns"] == nil {
            print("Warning: Table requires 'columns'; defaulting to empty")
            validatedProperties["columns"] = []
        }
        validatedProperties["rows"] = validatedProperties["rows"] as? [[String]] ?? []
        if let columns = validatedProperties["columns"] as? [String],
           let widths = validatedProperties["widths"] as? [Int],
           widths.count > columns.count {
            print("Warning: Table widths count (\(widths.count)) exceeds columns count (\(columns.count)); ignoring extra widths")
            validatedProperties["widths"] = Array(widths.prefix(columns.count))
        }
        if let columns = validatedProperties["columns"] as? [String],
           let rows = validatedProperties["rows"] as? [[String]] {
            validatedProperties["rows"] = rows.map { row in
                if row.count < columns.count {
                    print("Warning: Table row has \(row.count) values, expected \(columns.count); padding with empty strings")
                    return row + Array(repeating: "", count: columns.count - row.count)
                } else if row.count > columns.count {
                    print("Warning: Table row has \(row.count) values, expected \(columns.count); truncating")
                    return Array(row.prefix(columns.count))
                }
                return row
            }
        }
        if let doubleClickActionID = validatedProperties["doubleClickActionID"] as? String {
            validatedProperties["doubleClickActionID"] = doubleClickActionID
        } else if validatedProperties["doubleClickActionID"] != nil {
            print("Warning: Table doubleClickActionID must be a string; ignoring")
            validatedProperties["doubleClickActionID"] = nil
        }
        #else
        if validatedProperties["columns"] == nil {
            validatedProperties["columns"] = []
        }
        validatedProperties["rows"] = []
        validatedProperties["widths"] = []
        validatedProperties["doubleClickActionID"] = nil
        print("Warning: Table is macOS-only; using default values for non-macOS platforms")
        #endif
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        #if os(macOS)
        let columns = (validatedProperties["columns"] as? [String]) ?? []
        let widths = (validatedProperties["widths"] as? [Int]) ?? []
        let rows = ((validatedProperties["rows"] as? [[String]]) ?? []).map { TableRow(id: UUID().uuidString, values: $0) }
        let selectionBinding = Binding(
            get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String },
            set: { newValue in
                state.wrappedValue[element.id] = ["value": newValue ?? ""]
                if let actionID = validatedProperties["actionID"] as? String {
                    actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
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
            .onTapGesture(count: 2) {
                if let doubleClickActionID = doubleClickActionID,
                   let selectedRow = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String {
                    actionHandler(doubleClickActionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
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
