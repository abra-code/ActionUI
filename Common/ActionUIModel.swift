import SwiftUI

@MainActor
class ActionUIModel: ObservableObject {
    static let shared = ActionUIModel()
    
    @Published var descriptions: [String: ActionUIElement] = [:]
    @Published var states: [String: [Int: Any]] = [:]
    
    // Registry for action handlers, mapping actionID to closures that handle user interactions
    private var actionHandlers: [String: (String, String, Int, Int) -> Void] = [:]
    
    // Default handler for actions with no specific handler registered, used for all unmatched actionIDs
    private var defaultActionHandler: ((String, String, Int, Int) -> Void)?
    
    // Register a handler for a specific actionID
    // Parameters:
    // - actionID: The identifier for the action (e.g., "button.click", "table.doubleClick")
    // - handler: Closure to execute when the actionID is triggered
    func registerActionHandler(for actionID: String, handler: @escaping (String, String, Int, Int) -> Void) {
        actionHandlers[actionID] = handler
    }
    
    // Unregister a handler for a specific actionID
    func unregisterActionHandler(for actionID: String) {
        actionHandlers.removeValue(forKey: actionID)
    }
    
    // Set the default handler for unmatched actionIDs
    func setDefaultActionHandler(_ handler: @escaping (String, String, Int, Int) -> Void) {
        defaultActionHandler = handler
    }
    
    // Remove the default handler
    func removeDefaultActionHandler() {
        defaultActionHandler = nil
    }
    
    // Execute the handler for an actionID, falling back to defaultActionHandler if no specific handler is found
    // Uses ActionUIModel.shared for state access
    func actionHandler(_ actionID: String, windowUUID: String, viewID: Int, controlPartID: Int) {
        if let handler = actionHandlers[actionID] {
            handler(actionID, windowUUID, viewID, controlPartID)
        } else if let defaultHandler = defaultActionHandler {
            defaultHandler(actionID, windowUUID, viewID, controlPartID)
        } else {
            print("Warning: No handler registered for actionID '\(actionID)' and no default handler set")
        }
    }
    
    func loadDescription(from data: Data, format: String, windowUUID: String) throws {
        if format == "json" {
            let element = try JSONDecoder().decode(StaticElement.self, from: data)
            descriptions[windowUUID] = element
        } else if format == "plist" {
            let element = try PropertyListDecoder().decode(StaticElement.self, from: data)
            descriptions[windowUUID] = element
        } else {
            throw NSError(domain: "ActionUIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }
    
    func cacheAsBinaryPlist(_ data: Data, format: String, to url: URL, windowUUID: String) throws {
        try loadDescription(from: data, format: format, windowUUID: windowUUID)
        let plistData = try PropertyListEncoder().encode(descriptions[windowUUID]!)
        try plistData.write(to: url)
    }
    
    func state(for windowUUID: String) -> Binding<[Int: Any]> {
        Binding(
            get: { self.states[windowUUID] ?? [:] },
            set: { self.states[windowUUID] = $0 }
        )
    }
    
    // Retrieves the value of a view based on viewID and controlPartID
    // For Table/List with [[String]] content, controlPartID == 0 returns tab-separated values, controlPartID >= 1 returns the indexed column (or "" if out of bounds)
    // For List with [String] content or other views, returns the "value" from state
    func getControlValue(windowUUID: String, viewID: Int, controlPartID: Int = 0) -> Any? {
        guard let state = states[windowUUID]?[viewID] as? [String: Any] else {
            return nil
        }
        
        // Handle Table or List with multi-column content
        // Design decision: Preserve extra columns in "content" beyond displayed columns to support runtime data (e.g., database IDs)
        if let content = state["content"] as? [[String]],
           let selectedRow = state["value"] as? [String] {
            if controlPartID == 0 {
                return selectedRow.joined(separator: "\t")
            } else if controlPartID > 0 {
                return selectedRow.count > controlPartID - 1 ? selectedRow[controlPartID - 1] : ""
            }
            return nil
        } else if let selectedItem = state["value"] as? String {
            // Handle List with single-column content
            return selectedItem
        }
        
        // Fallback for other views (e.g., Button, TextField)
        return state["value"]
    }
    
    // Sets the value of a view, updating its state and validatedProperties
    // For Table: Accepts [[String]], preserves all columns, pads rows for display if needed
    // For List: Accepts [String] or [[String]], converts [String] to [[String]] for consistency
    // For other views: Sets "value" directly
    func setControlValue(windowUUID: String, viewID: Int, value: Any, controlPartID: Int = 0) {
        var controlState = states[windowUUID]?[viewID] as? [String: Any] ?? ["value": "", "content": []]
        
        if let newRows = value as? [[String]],
           let validatedProperties = controlState["validatedProperties"] as? [String: Any],
           let columns = validatedProperties["columns"] as? [String] {
            // Table: Pad rows for display, preserve all columns in content
            let validatedRows = newRows.map { row in
                if row.count < columns.count {
                    print("Warning: Row has \(row.count) values, expected at least \(columns.count); padding with empty strings")
                    return row + Array(repeating: "", count: columns.count - row.count)
                }
                return row
            }
            controlState["content"] = newRows
            if let selectedRow = controlState["value"] as? [String],
               !newRows.contains(where: { $0.first == selectedRow.first }) {
                controlState["selectedRowID"] = nil
                controlState["value"] = [] as [String]
            }
            if var validatedProperties = controlState["validatedProperties"] as? [String: Any] {
                validatedProperties["rows"] = validatedRows
                controlState["validatedProperties"] = validatedProperties
            }
        } else if let newItems = value as? [String] {
            // List: Convert [String] to [[String]] for consistency
            let newContent = newItems.map { [$0] }
            controlState["content"] = newContent
            if let selectedRow = controlState["value"] as? [String],
               !newContent.contains(where: { $0.first == selectedRow.first }) {
                controlState["value"] = [] as [String]
            } else if let selectedItem = controlState["value"] as? String,
                      !newItems.contains(selectedItem) {
                controlState["value"] = ""
            }
            if var validatedProperties = controlState["validatedProperties"] as? [String: Any] {
                validatedProperties["items"] = newContent
                controlState["validatedProperties"] = validatedProperties
            }
        } else {
            // Other views (e.g., Button, TextField)
            controlState["value"] = value
        }
        
        states[windowUUID, default: [:]][viewID] = controlState
    }
    
    // Appends items to a view’s content, updating state and validatedProperties
    // For Table: Appends [[String]], preserves all columns, pads rows for display
    // For List: Appends [String] or [[String]], converts [String] to [[String]]
    func appendItems(windowUUID: String, viewID: Int, items: Any) {
        var controlState = states[windowUUID]?[viewID] as? [String: Any] ?? ["content": [], "value": ""]
        
        if let newRows = items as? [[String]],
           let validatedProperties = controlState["validatedProperties"] as? [String: Any],
           let columns = validatedProperties["columns"] as? [String],
           var currentContent = controlState["content"] as? [[String]] {
            // Table: Append full rows, validate for display
            let validatedRows = newRows.map { row in
                if row.count < columns.count {
                    print("Warning: Row has \(row.count) values, expected at least \(columns.count); padding with empty strings")
                    return row + Array(repeating: "", count: columns.count - row.count)
                }
                return row
            }
            currentContent.append(contentsOf: newRows)
            controlState["content"] = currentContent
            if var validatedProperties = controlState["validatedProperties"] as? [String: Any] {
                validatedProperties["rows"] = currentContent.map { row in
                    row.count < columns.count ? row + Array(repeating: "", count: columns.count - row.count) : row
                }
                controlState["validatedProperties"] = validatedProperties
            }
        } else if let newItems = items as? [String],
                  var currentContent = controlState["content"] as? [[String]] {
            // List: Convert [String] to [[String]] and append
            let newContent = newItems.map { [$0] }
            currentContent.append(contentsOf: newContent)
            controlState["content"] = currentContent
            if var validatedProperties = controlState["validatedProperties"] as? [String: Any] {
                validatedProperties["items"] = currentContent
                controlState["validatedProperties"] = validatedProperties
            }
        }
        
        states[windowUUID, default: [:]][viewID] = controlState
    }
}
