/*
 ActionUIModel manages the state of UI elements across windows and provides methods to get/set properties and values.
 State is stored in a nested dictionary: states[windowUUID][viewID][key], where keys include "value", "validatedProperties", and view-specific data (e.g., "content", "selectedRowID").
 */

import SwiftUI
import MapKit

@MainActor
class ActionUIModel: ObservableObject {
    // Singleton instance for centralized state management
    // Design decision: Singleton ensures a single source of truth for descriptions and states, used by all views and action handlers
    static let shared = ActionUIModel()
    
    // Stores view hierarchies by windowUUID, loaded from JSON or plist
    // Design decision: @Published ensures SwiftUI refreshes when descriptions change
    @Published var descriptions: [String: ActionUIElement] = [:]
    
    // Stores view state (value, content, validatedProperties) by windowUUID and viewID
    // Design decision: @Published enables automatic SwiftUI updates when state changes, with viewID ensuring isolated refreshes
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
    func actionHandler(_ actionID: String, windowUUID: String, viewID: Int, viewPartID: Int) {
        if let handler = actionHandlers[actionID] {
            handler(actionID, windowUUID, viewID, viewPartID)
        } else if let defaultHandler = defaultActionHandler {
            defaultHandler(actionID, windowUUID, viewID, viewPartID)
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
    
    // Retrieves the value of a view based on viewID and viewPartID
    // For Table/List with [[String]] content, viewPartID == 0 returns tab-separated values, viewPartID >= 1 returns the indexed column (or "" if out of bounds)
    // For List with [String] content or other views, returns the "value" from state
    func getElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> Any? {
        guard let state = states[windowUUID]?[viewID] as? [String: Any] else {
            return nil
        }
        
        // Handle Table or List with multi-column content
        // Design decision: Preserve extra columns in "content" beyond displayed columns to support runtime data (e.g., database IDs)
        if let content = state["content"] as? [[String]],
           let selectedRow = state["value"] as? [String] {
            if viewPartID == 0 {
                return selectedRow.joined(separator: "\t")
            } else if viewPartID > 0 {
                return selectedRow.count > viewPartID - 1 ? selectedRow[viewPartID - 1] : ""
            }
            return nil
        } else if let selectedItem = state["value"] as? String {
            // Handle List with single-column content
            return selectedItem
        }
        
        // Fallback for other views (e.g., Button, TextField, Toggle, Slider, ColorPicker, DatePicker)
        return state["value"]
    }
    
    // Sets the value of a view, updating its state and validatedProperties
    // For Table: Accepts [[String]], preserves all columns, pads rows for display if needed
    // For List: Accepts [String] or [[String]], converts [String] to [[String]] for consistency
    // For other views: Sets "value" directly
    func setElementValue(windowUUID: String, viewID: Int, value: Any, viewPartID: Int = 0) {
        var controlState = states[windowUUID]?[viewID] as? [String: Any] ?? [:]
        
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
                controlState["value"] = []
            }
            if var validatedProperties = controlState["validatedProperties"] as? [String: Any] {
                validatedProperties["items"] = newContent
                controlState["validatedProperties"] = validatedProperties
            }
        } else {
            // Other views (e.g., Button, TextField, Toggle, Slider, ColorPicker, DatePicker)
            controlState["value"] = value
        }
        
        states[windowUUID, default: [:]][viewID] = controlState
    }
    
    // Converts control value to a string representation for scripting
    // Design decision: Returns non-optional String, using "" for nil, invalid conversions, or unsupported types; uses ISO 8601 for Date; uses JSON for CLLocationCoordinate2D
    func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> String {
        guard let value = getElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID) else {
            return ""
        }
        
        switch value {
        case let array as [String]:
            return array.joined(separator: "\t")
        case let arrayArray as [[String]]:
            return arrayArray.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        case let color as Color:
            if let hex = ColorHelper.colorToHex(color) {
                return hex
            }
            return ""
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as Int:
            return String(number)
        case let number as Double:
            return String(number)
        case let number as Float:
            return String(number)
        case let string as String:
            return string
        case let date as Date:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            return formatter.string(from: date)
        case let coordinate as CLLocationCoordinate2D:
            // Design decision: Serializes CLLocationCoordinate2D as JSON string matching Map's coordinate property format
            return "{\"latitude\":\(coordinate.latitude),\"longitude\":\(coordinate.longitude)}"
        default:
            print("Warning: Unsupported value type for getElementValueAsString: \(type(of: value))")
            return ""
        }
    }
    
    // Converts a string to the view's value type and delegates to setElementValue
    // Design decision: Uses view's declared valueType to parse string, ensuring type safety and modularity; supports ISO 8601 for Date; supports JSON for CLLocationCoordinate2D
    func setElementValueFromString(windowUUID: String, viewID: Int, viewPartID: Int = 0, stringValue: String) {
        guard let element = descriptions[windowUUID]?.findElement(by: viewID) else {
            print("Warning: No view found for windowUUID '\(windowUUID)' and viewID '\(viewID)'")
            return
        }
        
        var value: Any?
        
        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: element.type)
        if valueType == [String].self {
            value = stringValue.split(separator: "\t").map { String($0) }
        } else if valueType == [[String]].self {
            value = stringValue.split(separator: "\n").map { row in
                row.split(separator: "\t").map { String($0) }
            }
        } else if valueType == Bool.self {
            if stringValue.lowercased() == "true" {
                value = true
            } else if stringValue.lowercased() == "false" {
                value = false
            } else {
                print("Warning: Invalid string for Bool value: \(stringValue); ignoring")
                return
            }
        } else if valueType == Color.self {
            if let color = ColorHelper.resolveColor(stringValue) {
                value = color
            } else {
                print("Warning: Invalid color string: \(stringValue); ignoring")
                return
            }
        } else if valueType == Double.self {
            if let doubleValue = Double(stringValue) {
                value = doubleValue
            } else {
                print("Warning: Invalid string for Double value: \(stringValue); ignoring")
                return
            }
        } else if valueType == Float.self {
            if let floatValue = Float(stringValue) {
                value = floatValue
            } else {
                print("Warning: Invalid string for Float value: \(stringValue); ignoring")
                return
            }
        } else if valueType == Int.self {
            if let intValue = Int(stringValue) {
                value = intValue
            } else {
                print("Warning: Invalid string for Int value: \(stringValue); ignoring")
                return
            }
        } else if valueType == String.self {
            value = stringValue
        } else if valueType == Date.self {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: stringValue) {
                value = date
            } else {
                print("Warning: Invalid ISO 8601 date string: \(stringValue); ignoring")
                return
            }
        } else if valueType == CLLocationCoordinate2D.self {
            // Design decision: Parses JSON string into CLLocationCoordinate2D, matching Map's coordinate property format
            do {
                let data = stringValue.data(using: .utf8)!
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Double]
                if let latitude = json?["latitude"], let longitude = json?["longitude"] {
                    value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                } else {
                    print("Warning: Invalid coordinate format '\(stringValue)'; ignoring")
                    return
                }
            } catch {
                print("Warning: Failed to parse coordinate '\(stringValue)'; ignoring")
                return
            }
        } else if valueType == Void.self {
            print("Warning: View with Void valueType does not support setElementValueFromString: \(element.type)")
            return
        } else {
            print("Warning: Unsupported valueType for setElementValueFromString: \(valueType)")
            return
        }
        
        if let value = value {
            setElementValue(windowUUID: windowUUID, viewID: viewID, value: value, viewPartID: viewPartID)
        }
    }
    
    // Appends items to a view’s content, updating state and validatedProperties
    // For Table: Appends [[String]], preserves all columns, pads rows for display
    // For List: Appends [String] or [[String]], converts [String] to [[String]]
    func appendElementItems(windowUUID: String, viewID: Int, items: Any) {
        var controlState = states[windowUUID]?[viewID] as? [String: Any] ?? [:]
        
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
    
    // Retrieves a property value for a view by its name
    // Design decision: Accesses validatedProperties to ensure consistency with rendered views, as these are validated by ActionUIRegistry
    // Returns nil with a warning if the view or property is missing to prevent crashes and provide clear feedback for debugging
    func getElementProperty(windowUUID: String, viewID: Int, propertyName: String) -> Any? {
        guard let controlState = states[windowUUID]?[viewID] as? [String: Any],
              let validatedProperties = controlState["validatedProperties"] as? [String: Any] else {
            print("Warning: No state found for windowUUID '\(windowUUID)' and viewID '\(viewID)'")
            return nil
        }
        if let value = validatedProperties[propertyName] {
            return value
        }
        print("Warning: Property '\(propertyName)' not found for viewID '\(viewID)'")
        return nil
    }
    
    // Sets a property value for a view and re-validates it
    // Design decision: Re-validates using ActionUIRegistry to ensure type safety and HIG compliance (e.g., 'disabled' must be Bool)
    // Updates states[windowUUID][viewID] to trigger SwiftUI refresh, relying on viewID and @Published for isolated view updates
    // Uses findElement(by:) to get the view's type for validation
    func setElementProperty(windowUUID: String, viewID: Int, propertyName: String, value: Any) {
        guard let element = descriptions[windowUUID]?.findElement(by: viewID) else {
            print("Warning: No view found for windowUUID '\(windowUUID)' and viewID '\(viewID)'")
            return
        }
        
        // Initialize controlState with element.properties if not set
        // Design decision: Fallback to element.properties ensures state is initialized even if not previously set by buildElement
        var controlState = states[windowUUID]?[viewID] as? [String: Any] ?? ["validatedProperties": element.properties]
        var validatedProperties = controlState["validatedProperties"] as? [String: Any] ?? element.properties
        
        // Update the property
        validatedProperties[propertyName] = value
        
        // Re-validate to ensure compliance with view-specific rules
        // Design decision: Validation ensures properties like 'disabled' are correctly typed and defaults are applied (e.g., false for invalid 'disabled')
        let reValidatedProperties = ActionUIRegistry.shared.validateProperties(forElementType: element.type, properties: View.validateProperties(validatedProperties))
        
        // Update state to trigger refresh
        // Design decision: Storing in states[windowUUID][viewID] leverages @Published to notify SwiftUI, with viewID ensuring only the target view redraws
        controlState["validatedProperties"] = reValidatedProperties
        states[windowUUID, default: [:]][viewID] = controlState
    }
}

// Extension to find an element by ID in the element hierarchy
// Design decision: Recursive search supports nested JSON structures, enabling validation of properties for views at any depth
extension ActionUIElement {
    func findElement(by viewID: Int) -> ActionUIElement? {
        if self.id == viewID {
            return self
        }
        if let children = self.children {
            for child in children {
                if let found = child.findElement(by: viewID) {
                    return found
                }
            }
        }
        return nil
    }
}
