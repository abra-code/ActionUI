// Common/ActionUIModel.swift
import SwiftUI
import MapKit
import Combine

/*
 ActionUIModel manages the global state for ActionUI, including view descriptions and state.
 It provides methods to load view descriptions, handle actions, and manage element state.
 The singleton pattern ensures a single source of truth for the UI state.
 Design decision: Made public to support ActionUISwift adapter, with internal/private access for state to preserve encapsulation.
*/

@MainActor
public class ActionUIModel: ObservableObject {
    // Singleton instance for global access
    public static let shared = ActionUIModel()
    
    // Dictionary of windowUUID to WindowModel containing descriptions and viewModels
    internal var windowModels: [String: WindowModel] = [:]
    
    // Registered action handlers for specific actionIDs
    internal var actionHandlers: [String: (String, String, Int, Int, Any?) -> Void] = [:]
    
    // Default handler for actions with no specific handler registered, used for all unmatched actionIDs
    private var defaultActionHandler: ((String, String, Int, Int, Any?) -> Void)?
    
    // Design decision: Public logger for client access, defaults to ConsoleLogger for consistency
    // Logger for debugging and error reporting
    public var logger: any ActionUILogger
    
    private init() {
        // Initialize with default ConsoleLogger
        self.logger = ConsoleLogger(maxLevel: .verbose)
    }
        
    // Register a handler for a specific actionID
    // Parameters:
    // - actionID: The identifier for the action (e.g., "button.click", "table.doubleClick")
    // - handler: Closure to execute when the actionID is triggered
    public func registerActionHandler(for actionID: String, handler: @escaping (String, String, Int, Int, Any?) -> Void) {
        actionHandlers[actionID] = handler
        logger.log("Registered handler for actionID: \(actionID)", .verbose)
    }
    
    // Unregister an action handler for a specific actionID
    public func unregisterActionHandler(for actionID: String) {
        actionHandlers.removeValue(forKey: actionID)
        logger.log("Unregistered handler for actionID: \(actionID)", .verbose)
    }
    
    // Set a default action handler for unregistered actionIDs
    public func setDefaultActionHandler(_ handler: @escaping (String, String, Int, Int, Any?) -> Void) {
        defaultActionHandler = handler
        logger.log("Set default action handler", .verbose)
    }
    
    // Remove the default action handler
    public func removeDefaultActionHandler() {
        defaultActionHandler = nil
        logger.log("Removed default action handler", .verbose)
    }
    
    // Execute the handler for an actionID, falling back to defaultActionHandler if no specific handler is found
    internal func actionHandler(_ actionID: String, windowUUID: String, viewID: Int, viewPartID: Int, context: Any? = nil) {
        if let handler = actionHandlers[actionID] {
            logger.log("Executing handler for actionID: \(actionID), viewID: \(viewID)", .debug)
            handler(actionID, windowUUID, viewID, viewPartID, context)
        } else if let defaultHandler = defaultActionHandler {
            logger.log("Executing default handler for actionID: \(actionID), viewID: \(viewID)", .debug)
            defaultHandler(actionID, windowUUID, viewID, viewPartID, context)
        } else {
            logger.log("No handler registered for actionID '\(actionID)' and no default handler set", .warning)
        }
    }
    
    // Load a view description from JSON or plist data for a specific windowUUID
    internal func loadDescription(from data: Data, format: String, windowUUID: String) throws -> ActionUIElement {
        let windowModel = windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        let element = try windowModel.loadDescription(from: data, format: format)
        windowModels[windowUUID] = windowModel
        return element
    }
    
    // Load a view description from a dictionary for a specific windowUUID
    internal func loadDescription(from dict: [String: Any], windowUUID: String) throws -> ActionUIElement {
        let windowModel = windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        let element = try windowModel.loadDescription(from: dict)
        windowModels[windowUUID] = windowModel
        return element
    }

    // Load a sub-view from JSON or plist data without overwriting the root element
    internal func loadSubViewDescription(from data: Data, format: String, windowUUID: String) throws -> ActionUIElement {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("No WindowModel found for windowUUID: \(windowUUID)", .error)
            throw NSError(domain: "ActionUIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No WindowModel for windowUUID"])
        }
        return try windowModel.loadSubViewDescription(from: data, format: format)
    }

    // Cache a view description as a binary plist to a specified URL
    internal func cacheAsBinaryPlist(_ data: Data, format: String, to url: URL, windowUUID: String) throws {
        let windowModel = windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        let element = try windowModel.loadDescription(from: data, format: format)
        let plistData = try PropertyListEncoder().encode(element)
        try plistData.write(to: url)
        logger.log("Cached description as binary plist for windowUUID: \(windowUUID) at \(url)", .verbose)
        windowModels[windowUUID] = windowModel
    }

    internal func cacheData(_ data: Data, format: String, to url: URL, windowUUID: String) throws {
        try data.write(to: url)
        logger.log("Cached description in original format for windowUUID: \(windowUUID) at \(url)", .verbose)
    }

    // Get the value of a view element
    public func getElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> Any? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No ViewModel found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        
        // Handle Table or List with multi-column content
        // Design decision: Preserve extra columns in "content" beyond displayed columns to support runtime data (e.g., database IDs)
        if let _ = viewModel.states["content"] as? [[String]], let selectedRow = viewModel.value as? [String] {
            if viewPartID == 0 {
                return selectedRow.joined(separator: "\t")
            } else if viewPartID > 0 {
                return (selectedRow.count > (viewPartID - 1)) ? selectedRow[viewPartID - 1] : ""
            }
            logger.log("Invalid viewPartID \(viewPartID) for multi-column content", .warning)
            return nil
            // Handle List with single-column content
        } else if let selectedItem = viewModel.value as? String {
            return selectedItem
        }
        // Fallback for other views (e.g., Button, TextField, Toggle, Slider, ColorPicker, DatePicker)
        return viewModel.value
    }
    
    // Sets the value of a view, updating its state and validatedProperties
    // For Table: Accepts [[String]], preserves all columns, pads rows for display if needed
    // For List: Accepts [String] or [[String]], converts [String] to [[String]] for consistency
    // For other views: Sets "value" directly
    public func setElementValue(windowUUID: String, viewID: Int, value: Any, viewPartID: Int = 0) {
        guard let windowModel = windowModels[windowUUID],
              let _ = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        if let newRows = value as? [[String]] {
            viewModel.objectWillChange.send()
            viewModel.states["content"] = newRows
            if let selectedRow = viewModel.value as? [String], !newRows.contains(where: { $0.first == selectedRow.first }) {
                viewModel.value = [] as [String]
            }
            logger.log("Updated Table content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        } else if let newItems = value as? [String] {
            // List: Convert [String] to [[String]] for consistency
            let newContent = newItems.map { [$0] }
            viewModel.objectWillChange.send()
            viewModel.states["content"] = newContent
            if let selectedRow = viewModel.value as? [String], !newContent.contains(where: { $0.first == selectedRow.first }) {
                viewModel.value = [] as [String]
            } else if let selectedItem = viewModel.value as? String, !newItems.contains(selectedItem) {
                viewModel.value = []
            }
            logger.log("Updated List content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        } else {
            // Other views (e.g., Button, TextField, Toggle, Slider, ColorPicker, DatePicker)
            viewModel.value = value
            logger.log("Set value for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        }
        windowModel.viewModels[viewID] = viewModel
    }
    
    // Converts control value to a string representation for scripting
    // Design decision: Returns non-optional String, using "" for nil, invalid conversions, or unsupported types; uses ISO 8601 for Date; uses JSON for CLLocationCoordinate2D
    public func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> String? {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        let viewModel = windowModel.viewModels[viewID]
        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: element.type)
        
        if let _ = viewModel?.states["content"] as? [[String]], let selectedRow = viewModel?.value as? [String] {
            if viewPartID == 0 {
                return selectedRow.joined(separator: "\t")
            } else if viewPartID > 0 {
                return (selectedRow.count > (viewPartID - 1)) ? selectedRow[viewPartID - 1] : ""
            }
            logger.log("Invalid viewPartID \(viewPartID) for multi-column content", .warning)
            return nil
        } else if let selectedItem = viewModel?.value as? String {
            return selectedItem
        } else if let value = viewModel?.value {
            if valueType == Bool.self, let boolValue = value as? Bool {
                return boolValue.description
            } else if valueType == Color.self, let color = value as? Color {
                return ColorHelper.colorToHex(color) ?? ""
            } else if valueType == Double.self, let doubleValue = value as? Double {
                return String(doubleValue)
            } else if valueType == Float.self, let floatValue = value as? Float {
                return String(floatValue)
            } else if valueType == Int.self, let intValue = value as? Int {
                return String(intValue)
            } else if valueType == Date.self, let date = value as? Date {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                return formatter.string(from: date)
            } else if valueType == CLLocationCoordinate2D.self, let coordinate = value as? CLLocationCoordinate2D {
                return "{\"latitude\":\(coordinate.latitude),\"longitude\":\(coordinate.longitude)}"
            } else if valueType == [String].self, let stringArray = value as? [String] {
                return stringArray.joined(separator: "\t")
            } else if valueType == [[String]].self, let stringTable = value as? [[String]] {
                return stringTable.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            }
            return String(describing: value)
        }
        return nil
    }
    
    // Converts a string to the view's value type and delegates to setElementValue
    // Design decision: Uses view's declared valueType to parse string, ensuring type safety and modularity; supports ISO 8601 for Date; supports JSON for CLLocationCoordinate2D
    public func setElementValueFromString(windowUUID: String, viewID: Int, value: String, viewPartID: Int = 0) {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let _ = windowModel.viewModels[viewID] ?? ViewModel()
        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: element.type)
        var convertedValue: Any?
        
        if valueType == [String].self {
            convertedValue = value.split(separator: "\t").map { String($0) }
        } else if valueType == [[String]].self {
            convertedValue = value.split(separator: "\n").map { row in
                row.split(separator: "\t").map { String($0) }
            }
        } else if valueType == Bool.self {
            if value.lowercased() == "true" {
                convertedValue = true
            } else if value.lowercased() == "false" {
                convertedValue = false
            } else {
                logger.log("Invalid string for Bool value: \(value) for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == Color.self {
            if let color = ColorHelper.resolveColor(value) {
                convertedValue = color
            } else {
                logger.log("Invalid color string: \(value) for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == Double.self {
            if let doubleValue = Double(value) {
                convertedValue = doubleValue
            } else {
                logger.log("Invalid string for Double value: \(value) for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == Float.self {
            if let floatValue = Float(value) {
                convertedValue = floatValue
            } else {
                logger.log("Invalid string for Float value: \(value) for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == Int.self {
            if let intValue = Int(value) {
                convertedValue = intValue
            } else {
                logger.log("Invalid string for Int value: \(value) for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == String.self {
            convertedValue = value
        } else if valueType == Date.self {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: value) {
                convertedValue = date
            } else {
                logger.log("Invalid ISO 8601 date string: \(value) for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == CLLocationCoordinate2D.self {
            // Design decision: Parses JSON string into CLLocationCoordinate2D, matching Map's coordinate property format
            do {
                let data = value.data(using: .utf8)!
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Double]
                if let latitude = json?["latitude"], let longitude = json?["longitude"] {
                    convertedValue = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                } else {
                    logger.log("Invalid coordinate format '\(value)' for viewID: \(viewID)", .warning)
                    return
                }
            } catch {
                logger.log("Failed to parse coordinate '\(value)' for viewID: \(viewID)", .warning)
                return
            }
        } else if valueType == Void.self {
            logger.log("View with Void valueType does not support setElementValueFromString: \(element.type) for viewID: \(viewID)", .warning)
            return
        } else {
            logger.log("Unsupported valueType for setElementValueFromString: \(valueType) for viewID: \(viewID)", .warning)
            return
        }
        
        if let convertedValue {
            setElementValue(windowUUID: windowUUID, viewID: viewID, value: convertedValue, viewPartID: viewPartID)
        }
    }

    // MARK: - Element State API

    // Returns the current value for a single state key, or nil if the view or key is not found.
    public func getElementState(windowUUID: String, viewID: Int, key: String) -> Any? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No ViewModel found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        if let value = viewModel.states[key] {
            return value
        }
        logger.log("State key '\(key)' not found for viewID: \(viewID)", .warning)
        return nil
    }

    // Returns the string representation of a single state value.
    // Design decision: Uses pattern matching on the concrete type rather than a fixed registry,
    // because state types are set by view implementations and are not declared statically.
    public func getElementStateAsString(windowUUID: String, viewID: Int, key: String) -> String? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No ViewModel found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        guard let value = viewModel.states[key] else {
            logger.log("State key '\(key)' not found for viewID: \(viewID)", .warning)
            return nil
        }
        switch value {
        case let b as Bool:   return b.description
        case let d as Double: return String(d)
        case let f as Float:  return String(f)
        case let i as Int:    return String(i)
        case let s as String: return s
        default:              return String(describing: value)
        }
    }

    // Sets a single state key to a new value.
    // Design decision: Rejects updates that would change the type of an existing key to prevent
    // type corruption that would break setElementStateFromString's type-guided parsing.
    public func setElementState(windowUUID: String, viewID: Int, key: String, value: Any) {
        guard let windowModel = windowModels[windowUUID],
              let _ = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        if let existing = viewModel.states[key] {
            guard type(of: existing) == type(of: value) else {
                logger.log("Type mismatch for state key '\(key)' on viewID: \(viewID); expected \(type(of: existing)), got \(type(of: value))", .error)
                return
            }
        }
        viewModel.objectWillChange.send()
        viewModel.states[key] = value
        windowModel.viewModels[viewID] = viewModel
        logger.log("Set state '\(key)' for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Parses a string into the type of the existing state value and stores it.
    // Uses type(of: existing) for O(1) type detection without trying every possible cast.
    // If the key does not yet exist, stores the string as-is.
    public func setElementStateFromString(windowUUID: String, viewID: Int, key: String, value: String) {
        guard let windowModel = windowModels[windowUUID],
              let _ = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        let converted: Any
        if let existing = viewModel.states[key] {
            let t = type(of: existing)
            if t == Bool.self {
                if value.lowercased() == "true" {
                    converted = true
                } else if value.lowercased() == "false" {
                    converted = false
                } else {
                    logger.log("Invalid string for Bool state key '\(key)': \(value)", .warning)
                    return
                }
            } else if t == Double.self {
                guard let d = Double(value) else {
                    logger.log("Invalid string for Double state key '\(key)': \(value)", .warning)
                    return
                }
                converted = d
            } else if t == Float.self {
                guard let f = Float(value) else {
                    logger.log("Invalid string for Float state key '\(key)': \(value)", .warning)
                    return
                }
                converted = f
            } else if t == Int.self {
                guard let i = Int(value) else {
                    logger.log("Invalid string for Int state key '\(key)': \(value)", .warning)
                    return
                }
                converted = i
            } else if t == String.self {
                converted = value
            } else {
                logger.log("Unsupported state type \(t) for key '\(key)' on viewID: \(viewID)", .warning)
                return
            }
        } else {
            // Key does not exist yet — attempt JSON type inference so callers can establish
            // Bool/Int/Double/Array/Object state in one call without a prior typed setter.
            // Pre-scan avoids the NSError allocation cost of a failed parse for plain strings,
            // which are the most common expected type.
            if JSONHelper.looksLikeJSONFragment(value),
               let data = value.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) {
                converted = JSONHelper.normalizedJSONValue(parsed)
            } else {
                converted = value   // plain string
            }
        }
        viewModel.objectWillChange.send()
        viewModel.states[key] = converted
        windowModel.viewModels[viewID] = viewModel
        logger.log("Set state '\(key)' from string for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }


    // Retrieves a property value for a view by its name
    // Design decision: Accesses validatedProperties to ensure consistency with rendered views, as these are validated by ActionUIRegistry
    // Returns nil with a warning if the view or property is missing to prevent crashes and provide clear feedback for debugging
    public func getElementProperty(windowUUID: String, viewID: Int, propertyName: String) -> Any? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No ViewModel found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        if let value = viewModel.validatedProperties[propertyName] {
            return value
        }
        logger.log("Property '\(propertyName)' not found for viewID: \(viewID)", .warning)
        return nil
    }
    
    // Returns the number of data columns for a table/list view.
    // Uses the actual content rows to determine column count, which may exceed the number
    // of visible columns defined in the JSON — this supports hidden columns beyond the
    // displayed ones (e.g., a hidden ID column needed at runtime but not shown to the user).
    // Falls back to validatedProperties["columns"].count if content is not yet loaded.
    // Returns 0 for non-table elements, or if the view is not found.
    public func getElementColumnCount(windowUUID: String, viewID: Int) -> Int {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No ViewModel found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return 0
        }
        // Use actual content data: supports hidden columns beyond visible columns
        if let content = viewModel.states["content"] as? [[String]], !content.isEmpty {
            return content.map { $0.count }.max() ?? 0
        }
        // Fall back to visible column count before any content is loaded
        if let columns = viewModel.validatedProperties["columns"] as? [String] {
            return columns.count
        }
        return 0
    }

    // Returns all content rows for a table view element.
    // Returns nil if the view is not found or is not a table.
    public func getElementRows(windowUUID: String, viewID: Int) -> [[String]]? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No ViewModel found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        return viewModel.states["content"] as? [[String]]
    }

    // Sets all content rows for a table/list view element, replacing any existing rows.
    // Clears the current selection if the selected row is no longer present.
    public func setElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        guard let windowModel = windowModels[windowUUID],
              let _ = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        viewModel.objectWillChange.send()
        viewModel.states["content"] = rows
        if let selectedRow = viewModel.value as? [String], !rows.contains(where: { $0.first == selectedRow.first }) {
            viewModel.value = [] as [String]
        }
        windowModel.viewModels[viewID] = viewModel
        logger.log("Set \(rows.count) rows for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Clears all content rows from a table/list view element, preserving column definitions.
    public func clearElementRows(windowUUID: String, viewID: Int) {
        guard let windowModel = windowModels[windowUUID],
              let _ = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        viewModel.objectWillChange.send()
        viewModel.states["content"] = [] as [[String]]
        if viewModel.value is [String] {
            viewModel.value = [] as [String]
        }
        windowModel.viewModels[viewID] = viewModel
        logger.log("Cleared table rows for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Appends rows to a table/list view element's existing content.
    public func appendElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        guard let windowModel = windowModels[windowUUID],
              let _ = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        viewModel.objectWillChange.send()
        let existingContent = viewModel.states["content"] as? [[String]] ?? []
        viewModel.states["content"] = existingContent + rows
        windowModel.viewModels[viewID] = viewModel
        logger.log("Appended \(rows.count) rows to table viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Returns a dictionary mapping positive (user-assigned) view IDs to their view type strings for a given window.
    // Negative IDs are auto-assigned and excluded; 0 is not a valid ID.
    // Design decision: Traverses the element tree rather than viewModels to avoid exposing auto-assigned negative IDs
    public func getElementInfo(windowUUID: String) -> [Int: String] {
        guard let windowModel = windowModels[windowUUID],
              let rootElement = windowModel.element else {
            logger.log("No window found for windowUUID: \(windowUUID)", .warning)
            return [:]
        }
        var result: [Int: String] = [:]
        collectElementInfo(from: rootElement, into: &result)
        return result
    }

    // Recursively collects element IDs and types from the element tree
    private func collectElementInfo(from element: any ActionUIElementBase, into result: inout [Int: String]) {
        if element.id > 0 {
            result[element.id] = element.type
        }
        guard let subviews = element.subviews else { return }
        if let children = subviews["children"] as? [any ActionUIElementBase] {
            for child in children {
                collectElementInfo(from: child, into: &result)
            }
        }
        if let rows = subviews["rows"] as? [[any ActionUIElementBase]] {
            for row in rows {
                for child in row {
                    collectElementInfo(from: child, into: &result)
                }
            }
        }
        if let commands = subviews["commands"] as? [any ActionUIElementBase] {
            for command in commands {
                collectElementInfo(from: command, into: &result)
            }
        }
        for key in ["content", "destination", "sidebar", "detail"] {
            if let child = subviews[key] as? any ActionUIElementBase {
                collectElementInfo(from: child, into: &result)
            }
        }
    }

    // Sets a property value for a view and re-validates it
    // Design decision: Re-validates using ActionUIRegistry to ensure type safety and HIG compliance (e.g., 'disabled' must be Bool)
    // Updates validatedProperties to preserve runtime mutations and trigger SwiftUI refresh via viewModels
    public func setElementProperty(windowUUID: String, viewID: Int, propertyName: String, value: Any) {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.element?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel()
        // Notify SwiftUI before mutating the non-published validatedProperties,
        // matching the willSet contract expected by ObservableObject observers.
        viewModel.objectWillChange.send()
        viewModel.validatedProperties[propertyName] = value
        // Re-validate to ensure type safety and HIG compliance
        viewModel.validateProperties(viewModel.validatedProperties, elementType: element.type, logger: logger)
        logger.log("Set property '\(propertyName)' to \(value) for viewID: \(viewID)", .debug)
    }
}
