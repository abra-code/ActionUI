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
   // Note: These properties are specific to Table. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct Table: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
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
        print("Warning: Table is macOS-only; defaulting to empty properties")
        validatedProperties = [:]
        #endif
        
        return validatedProperties
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(macOS)
        registry.register("Table") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let columns = (properties["columns"] as? [String]) ?? []
            let widths = (properties["widths"] as? [Int]) ?? []
            let rows = ((properties["rows"] as? [[String]]) ?? []).map { TableRow(id: UUID().uuidString, values: $0) }
            let selectionBinding = Binding(
                get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String },
                set: { newValue in
                    state.wrappedValue[element.id] = ["value": newValue ?? ""]
                    if let actionID = properties["actionID"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
            return AnyView(
                SwiftUI.Table(rows, selection: selectionBinding) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        SwiftUI.TableColumn(column, value: \.values[index]) { row in
                            SwiftUI.Text(row.values[index])
                        }
                        .width(widths.count > index ? CGFloat(widths[index]) : nil)
                    }
                }
                .onChange(of: state.wrappedValue[element.id]?["value"]) { newValue in
                    if let actionID = properties["actionID"] as? String, newValue != nil {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
                .onTapGesture(count: 2) {
                    if let actionID = properties["doubleClickActionID"] as? String,
                       let selectedRow = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String {
                        actionHandler(actionID, windowUUID: windowUUID, controlID: element.id, controlPartID: 0, model: ActionUIModel.shared)
                    }
                }
            )
        }
        #else
        registry.register("Table") { _, _, _ in
            print("Warning: Table is not supported on this platform")
            return AnyView(EmptyView())
        }
        #endif
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        // No specific modifiers beyond base View properties
    }
}

struct TableRow: Identifiable {
    let id: String
    let values: [String]
}
