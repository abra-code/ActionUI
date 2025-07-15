
/*
 Sample JSON for Table (macOS only):
 {
   "type": "Table",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "columns": ["Name", "Age"],           // Required: Array of strings for column headers
     "rows": [["Alice", "30"], ["Bob", "25"]], // Optional: Array of string arrays, defaults to []
     "widths": [100, 50],                 // Optional: Array of integers for column widths
     "commandID": "table.select",          // Optional: String for selection action identifier
     "doubleClickCommandID": "table.doubleClick", // Optional: String for double-click action
     "padding": 10.0,                     // Optional: CGFloat for padding
     "font": "body",                      // Optional: SwiftUI font (e.g., "title", "body")
     "foregroundColor": "blue",           // Optional: SwiftUI color (e.g., "red", "blue")
     "hidden": false                      // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct Table: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["columns", "rows", "widths", "commandID", "doubleClickCommandID", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        #if os(macOS)
        if properties["columns"] == nil {
            print("Warning: Table requires 'columns'; defaulting to empty")
            validatedProperties["columns"] = []
        }
        validatedProperties["rows"] = properties["rows"] as? [[String]] ?? []
        if let columns = properties["columns"] as? [String],
           let widths = properties["widths"] as? [Int],
           widths.count > columns.count {
            print("Warning: Table widths count (\(widths.count)) exceeds columns count (\(columns.count)); ignoring extra widths")
            validatedProperties["widths"] = Array(widths.prefix(columns.count))
        }
        if let columns = properties["columns"] as? [String],
           let rows = properties["rows"] as? [[String]] {
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
        #else
        print("Warning: Table is macOS-only; defaulting to empty properties")
        validatedProperties = [:]
        #endif
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Table; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        #if os(macOS)
        registry.register("Table") { element, state, dialogGUID in
            let properties = validateProperties(element.properties)
            let columns = (properties["columns"] as? [String]) ?? []
            let widths = (properties["widths"] as? [Int]) ?? []
            let rows = ((properties["rows"] as? [[String]]) ?? []).map { TableRow(id: UUID().uuidString, values: $0) }
            return AnyView(
                SwiftUI.Table(rows, selection: Binding(
                    get: { (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String },
                    set: { newValue in
                        state.wrappedValue[element.id] = ["value": newValue ?? ""]
                        if let commandID = properties["commandID"] as? String {
                            commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                        }
                    }
                )) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        SwiftUI.TableColumn(column, value: \.values[index]) { row in
                            SwiftUI.Text(row.values[index])
                        }
                        .width(widths.count > index ? CGFloat(widths[index]) : nil)
                    }
                }
                .onChange(of: state.wrappedValue[element.id]?["value"]) { newValue in
                    if let commandID = properties["commandID"] as? String, newValue != nil {
                        commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
                    }
                }
                .onTapGesture(count: 2) {
                    if let commandID = properties["doubleClickCommandID"] as? String,
                       let selectedRow = (state.wrappedValue[element.id] as? [String: Any])?["value"] as? String {
                        commandHandler(commandID, dialogGUID: dialogGUID, controlID: element.id, controlPartID: 0, model: UIModel.shared)
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
}

struct TableRow: Identifiable {
    let id: String
    let values: [String]
}
