// Common/ActionUIModel.swift
import SwiftUI
import MapKit
internal import Combine

/*
 ActionUIModel manages the global state for ActionUI, including view descriptions and state.
 It provides methods to load view descriptions, handle actions, and manage element state.
 The singleton pattern ensures a single source of truth for the UI state.
*/

@MainActor
class ActionUIModel: ObservableObject {
    // Singleton instance for global access
    static let shared = ActionUIModel()
    
    // Dictionary of windowUUID to WindowModel containing descriptions and viewModels
    @Published var windowModels: [String: WindowModel] = [:]
    
    // Registered action handlers for specific actionIDs
    internal var actionHandlers: [String: (String, String, Int, Int, Any?) -> Void] = [:]
    
    // Default handler for actions with no specific handler registered, used for all unmatched actionIDs
    private var defaultActionHandler: ((String, String, Int, Int, Any?) -> Void)?
    
    // Design decision: Client-configurable via setLogger, defaults to ConsoleLogger for consistency
    // Logger for debugging and error reporting
    private var logger: any ActionUILogger
    
    private init() {
        // Initialize with default ConsoleLogger
        self.logger = ConsoleLogger(maxLevel: .verbose)
    }
    
    // Allows clients to set a custom logger (e.g., XCTestLogger)
    func setLogger(_ logger: any ActionUILogger) {
        self.logger = logger
    }
    
    // Register a handler for a specific actionID
    // Parameters:
    // - actionID: The identifier for the action (e.g. "button.click", "table.doubleClick")
    // - handler: Closure to execute when the actionID is triggered
    func registerActionHandler(for actionID: String, handler: @escaping (String, String, Int, Int, Any?) -> Void) {
        actionHandlers[actionID] = handler
        logger.log("Registered handler for actionID: \(actionID)", .verbose)
    }
    
    // Unregister an action handler for a specific actionID
    func unregisterActionHandler(for actionID: String) {
        actionHandlers.removeValue(forKey: actionID)
        logger.log("Unregistered handler for actionID: \(actionID)", .verbose)
    }
    
    // Set a default action handler for unregistered actionIDs
    func setDefaultActionHandler(_ handler: @escaping (String, String, Int, Int, Any?) -> Void) {
        defaultActionHandler = handler
        logger.log("Set default action handler", .verbose)
    }
    
    // Remove the default action handler
    func removeDefaultActionHandler() {
        defaultActionHandler = nil
        logger.log("Removed default action handler", .verbose)
    }
    
    // Execute the handler for an actionID, falling back to defaultActionHandler if no specific handler is found
    func actionHandler(_ actionID: String, windowUUID: String, viewID: Int, viewPartID: Int, context: Any? = nil) {
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
    func loadDescription(from data: Data, format: String, windowUUID: String) throws {
        let windowModel = windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        try windowModel.loadDescription(from: data, format: format)
        windowModels[windowUUID] = windowModel
    }
    
    // Load a view description from a dictionary for a specific windowUUID
    func loadDescription(from dict: [String: Any], windowUUID: String) throws {
        let windowModel = windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        try windowModel.loadDescription(from: dict)
        windowModels[windowUUID] = windowModel
    }
    
    // Cache a view description as a binary plist to a specified URL
    func cacheAsBinaryPlist(_ data: Data, format: String, to url: URL, windowUUID: String) throws {
        let windowModel = windowModels[windowUUID] ?? WindowModel(windowUUID: windowUUID, logger: logger)
        try windowModel.loadDescription(from: data, format: format)
        guard let description = windowModel.description else {
            throw NSError(domain: "ActionUIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No description loaded"])
        }
        let plistData = try PropertyListEncoder().encode(description)
        try plistData.write(to: url)
        logger.log("Cached description as binary plist for windowUUID: \(windowUUID) at \(url)", .verbose)
        windowModels[windowUUID] = windowModel
    }
        
    // Get the value of a view element
    func getElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> Any? {
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
                return selectedRow.count > viewPartID - 1 ? selectedRow[viewPartID - 1] : ""
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
    func setElementValue(windowUUID: String, viewID: Int, value: Any, viewPartID: Int = 0) {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.description?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel(properties: element.properties)
        if let newRows = value as? [[String]], let columns = viewModel.validatedProperties["columns"] as? [String] {
            let validatedRows = newRows.map { row in
                (row.count < columns.count) ? row + Array(repeating: "", count: columns.count - row.count) : row
            }
            viewModel.states["content"] = newRows
            if let selectedRow = viewModel.value as? [String], !newRows.contains(where: { $0.first == selectedRow.first }) {
                viewModel.states["selectedRowID"] = nil
                viewModel.value = [] as [String]
            }
            viewModel.validatedProperties["rows"] = validatedRows
            logger.log("Updated Table content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        } else if let newItems = value as? [String] {
            // List: Convert [String] to [[String]] for consistency
            let newContent = newItems.map { [$0] }
            viewModel.states["content"] = newContent
            if let selectedRow = viewModel.value as? [String], !newContent.contains(where: { $0.first == selectedRow.first }) {
                viewModel.value = [] as [String]
            } else if let selectedItem = viewModel.value as? String, !newItems.contains(selectedItem) {
                viewModel.value = []
            }
            viewModel.validatedProperties["items"] = newContent
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
    func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0) -> String? {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.description?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        let viewModel = windowModel.viewModels[viewID]
        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: element.type)
        
        if let content = viewModel?.states["content"] as? [[String]], let selectedRow = viewModel?.value as? [String] {
            if viewPartID == 0 {
                return selectedRow.joined(separator: "\t")
            } else if viewPartID > 0 {
                return selectedRow.count > viewPartID - 1 ? selectedRow[viewPartID - 1] : ""
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
    func setElementValueFromString(windowUUID: String, viewID: Int, value: String, viewPartID: Int = 0) {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.description?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let _ = windowModel.viewModels[viewID] ?? ViewModel(properties: element.properties)
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
    
    // Appends items to a view’s content, updating state and validatedProperties
    // For Table: Appends [[String]], preserves all columns, pads rows for display
    // For List: Appends [String] or [[String]], converts [String] to [[String]]
    func appendElementItems(windowUUID: String, viewID: Int, items: Any) {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.description?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel(properties: element.properties)
        if let newRows = items as? [[String]], let columns = viewModel.validatedProperties["columns"] as? [String],
           var currentContent = viewModel.states["content"] as? [[String]] {
            currentContent.append(contentsOf: newRows)
            viewModel.states["content"] = currentContent
            viewModel.validatedProperties["rows"] = currentContent.map { row in
                (row.count < columns.count) ? row + Array(repeating: "", count: columns.count - row.count) : row
            }
            logger.log("Appended rows to Table content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
            // List: Convert [String] to [[String]] and append
        } else if let newItems = items as? [String], var currentContent = viewModel.states["content"] as? [[String]] {
            let newContent = newItems.map { [$0] }
            currentContent.append(contentsOf: newContent)
            viewModel.states["content"] = currentContent
            viewModel.validatedProperties["items"] = currentContent
            logger.log("Appended items to List content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        } else {
            logger.log("Invalid items type for appendElementItems, viewID: \(viewID)", .warning)
        }
        windowModel.viewModels[viewID] = viewModel
    }
    
    // Retrieves a property value for a view by its name
    // Design decision: Accesses validatedProperties to ensure consistency with rendered views, as these are validated by ActionUIRegistry
    // Returns nil with a warning if the view or property is missing to prevent crashes and provide clear feedback for debugging
    func getElementProperty(windowUUID: String, viewID: Int, propertyName: String) -> Any? {
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
    
    // Sets a property value for a view and re-validates it
    // Design decision: Re-validates using ActionUIRegistry to ensure type safety and HIG compliance (e.g., 'disabled' must be Bool)
    // Updates states[windowUUID][viewID] to trigger SwiftUI refresh, relying on viewID and @Published for isolated view updates
    // Uses findElement(by:) to get the view's type for validation
    func setElementProperty(windowUUID: String, viewID: Int, propertyName: String, value: Any) {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.description?.findElement(by: viewID) else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        let viewModel = windowModel.viewModels[viewID] ?? ViewModel(properties: element.properties)
        viewModel.properties[propertyName] = value
        let reValidatedProperties = ActionUIRegistry.shared.validateProperties(
            forElementType: element.type,
            properties: View.validateProperties(viewModel.properties, logger)
        )
        viewModel.validatedProperties = reValidatedProperties
        windowModel.viewModels[viewID] = viewModel
        logger.log("Set property '\(propertyName)' to \(value) for viewID: \(viewID)", .debug)
    }
}
