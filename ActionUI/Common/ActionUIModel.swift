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

    // MARK: - Window enumeration

    /// UUIDs of every window that currently has a model, sorted for stable output.
    /// A window gets a model when a description is loaded for it and loses it when
    /// the window is unregistered; the list is the only way for a client that did
    /// not create the windows itself (a remote binding, a test harness) to discover them.
    public var windowUUIDs: [String] {
        return windowModels.keys.sorted()
    }

    /// True when a window model exists for windowUUID. Unlike getElementInfo, which returns
    /// an empty dictionary both for an unknown window and for a window without positive
    /// IDs, this distinguishes the two.
    public func hasWindow(_ windowUUID: String) -> Bool {
        return windowModels[windowUUID] != nil
    }

    // Register a handler for a specific actionID
    // Parameters:
    // - actionID: The identifier for the action (e.g., "button.click", "table.double.click")
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
    public func actionHandler(_ actionID: String, windowUUID: String, viewID: Int, viewPartID: Int, context: Any? = nil) {
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
    
    // MARK: - Pull-to-refresh

    // Safety net: if the client never signals completion, end the refresh after this many
    // seconds so the spinner cannot hang indefinitely. Generous, since the spinner normally
    // ends as soon as the client delivers refreshed data (any mutation to the refreshing view
    // or its subtree). Kept an internal constant rather than a JSON property to avoid widening
    // the schema; promote it to a property only if a real need appears.
    // A `var` (not `let`) only so tests can lower it; production never mutates it.
    static var refreshTimeoutSeconds: Double = 60

    // Entry point for a scrollable view's `.refreshable` action (see List/ScrollView).
    // Marks the view refreshing, fires onRefreshActionID, then suspends until the client signals
    // completion — any element mutation targeting this view or its subtree (see endRefreshTargeting)
    // — or the safety timeout elapses. The `await` suspends the task and releases the main actor,
    // so the client's main-actor callbacks (e.g. setElementRows) run and end the refresh; the
    // main thread is never blocked, so there is no deadlock.
    public func runRefresh(windowUUID: String, viewID: Int, actionID: String) async {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("runRefresh: no view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }

        // Capture the subtree once so a mutation to any descendant ends the refresh.
        viewModel.refreshSubtreeIDs = windowModel.subtreeIDs(of: viewID) ?? [viewID]

        // Safety net: end the refresh if the client never signals within the timeout.
        let timeoutTask = Task { @MainActor [weak viewModel] in
            try? await Task.sleep(nanoseconds: UInt64(Self.refreshTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            viewModel?.endRefresh()
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            viewModel.refreshContinuation = continuation
            // Fire AFTER registering the continuation: a client that responds synchronously
            // from its handler (calling setElementRows inline) then finds the continuation and
            // resumes it, rather than the signal being missed before we suspend.
            actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0)
        }
        timeoutTask.cancel()
    }

    // Ends any in-flight refresh whose captured subtree includes viewID. Called from the
    // element-mutation APIs so the client's natural response to a refresh (delivering fresh
    // data to the view, or to anything inside it) retracts the spinner with no dedicated API.
    private func endRefreshTargeting(windowUUID: String, viewID: Int) {
        guard let windowModel = windowModels[windowUUID] else { return }
        for viewModel in windowModel.viewModels.values {
            if let subtree = viewModel.refreshSubtreeIDs, subtree.contains(viewID) {
                viewModel.endRefresh()
            }
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

    // Load a sub-view from JSON or plist data without overwriting the root element.
    // When parentID != 0, cleans up old child models before loading to support dynamic content swapping.
    internal func loadSubViewDescription(from data: Data, format: String, windowUUID: String, parentID: Int = 0) throws -> ActionUIElement {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("No WindowModel found for windowUUID: \(windowUUID)", .error)
            throw NSError(domain: "ActionUIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No WindowModel for windowUUID"])
        }
        return try windowModel.loadSubViewDescription(from: data, format: format, parentID: parentID)
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
                return selectedRow
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
    public func setElementValue(windowUUID: String, viewID: Int, viewPartID: Int = 0, value: Any) {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        if let newRows = value as? [[String]] {
            viewModel.objectWillChange.send()
            viewModel.mutationToken &+= 1
            viewModel.states["content"] = newRows
            if let selectedRow = viewModel.value as? [String], !newRows.contains(where: { $0.first == selectedRow.first }) {
                viewModel.value = [] as [String]
            }
            logger.log("Updated Table content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        } else if let newItems = value as? [String] {
            // List: Convert [String] to [[String]] for consistency
            let newContent = newItems.map { [$0] }
            viewModel.objectWillChange.send()
            viewModel.mutationToken &+= 1
            viewModel.states["content"] = newContent
            if let selectedRow = viewModel.value as? [String], !newContent.contains(where: { $0.first == selectedRow.first }) {
                viewModel.value = [] as [String]
            } else if let selectedItem = viewModel.value as? String, !newItems.contains(selectedItem) {
                viewModel.value = []
            }
            logger.log("Updated List content for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        } else {
            // Other views (e.g., Button, TextField, Toggle, Slider, ColorPicker, DatePicker)
            viewModel.objectWillChange.send()
            viewModel.mutationToken &+= 1
            viewModel.value = value
            logger.log("Set value for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        }
        windowModel.viewModels[viewID] = viewModel
        endRefreshTargeting(windowUUID: windowUUID, viewID: viewID)
    }

    // Converts control value to a string representation for scripting
    // Design decision: Returns non-optional String, using "" for nil, invalid conversions, or unsupported types; uses ISO 8601 for Date; uses JSON for CLLocationCoordinate2D
    public func getElementValueAsString(windowUUID: String, viewID: Int, viewPartID: Int = 0, contentType: String? = nil) -> String? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }

        // Dispatch to view-specific serializer when contentType is provided
        if let contentType,
           let serializer = ActionUIRegistry.shared.getStringContentSerializer(forElementType: viewModel.elementType),
           let value = viewModel.value,
           let result = serializer(value, contentType, logger) {
            return result
        }

        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: viewModel.elementType)

        if let _ = viewModel.states["content"] as? [[String]], let selectedRow = viewModel.value as? [String] {
            if viewPartID == 0 {
                return selectedRow.joined(separator: "\t")
            } else if viewPartID > 0 {
                return (selectedRow.count > (viewPartID - 1)) ? selectedRow[viewPartID - 1] : ""
            }
            logger.log("Invalid viewPartID \(viewPartID) for multi-column content", .warning)
            return nil
        } else if let selectedItem = viewModel.value as? String {
            return selectedItem
        } else if let value = viewModel.value {
            if valueType == Bool.self, let boolValue = value as? Bool {
                return boolValue.description
            } else if valueType == SwiftUI.Color.self, let color = value as? SwiftUI.Color {
                return ColorHelper.colorToHex(color) ?? ""
            } else if valueType == Double.self, let doubleValue = value as? Double {
                return String(doubleValue)
            } else if valueType == Float.self, let floatValue = value as? Float {
                return String(floatValue)
            } else if valueType == Int.self, let intValue = value as? Int {
                return String(intValue)
            } else if valueType == Date.self, let date = value as? Date {
                // Time-bearing DatePicker modes ("hourAndMinute"/"dateAndTime")
                // serialize a full ISO datetime so a host can read HH:mm; every
                // other Date-valued element (and date-only DatePickers) stays a
                // bare "YYYY-MM-DD" for backward compatibility.
                let components = viewModel.validatedProperties["displayedComponents"] as? String
                if viewModel.elementType == "DatePicker", ActionUI.DatePicker.isTimeBearing(components) {
                    return DateHelper.formatDateTime(from: date)
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                return formatter.string(from: date)
            } else if valueType == CLLocationCoordinate2D.self, let coordinate = value as? CLLocationCoordinate2D {
                return "{\"latitude\":\(coordinate.latitude),\"longitude\":\(coordinate.longitude)}"
            } else if valueType == [String].self, let stringArray = value as? [String] {
                return stringArray.joined(separator: "\t")
            } else if valueType == [[String]].self, let stringTable = value as? [[String]] {
                return stringTable.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            } else if let attributed = value as? AttributedString {
                return String(attributed.characters)
            }
            return String(describing: value)
        }
        return nil
    }

    // Converts a string to the view's value type and delegates to setElementValue
    // Design decision: Uses view's declared valueType to parse string, ensuring type safety and modularity; supports ISO 8601 for Date; supports JSON for CLLocationCoordinate2D
    public func setElementValueFromString(windowUUID: String, viewID: Int, viewPartID: Int = 0, value: String, contentType: String? = nil) {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }

        // Dispatch to view-specific parser when contentType is provided
        if let contentType,
           let parser = ActionUIRegistry.shared.getStringContentParser(forElementType: viewModel.elementType),
           let parsed = parser(value, contentType, logger) {
            setElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: parsed)
            return
        }

        let valueType = ActionUIRegistry.shared.getElementValueType(forElementType: viewModel.elementType)
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
        } else if valueType == SwiftUI.Color.self {
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
            // Parse flexibly: accept "YYYY-MM-DD", a full ISO datetime, or (for
            // time-bearing DatePicker modes) a bare "HH:mm". DateHelper handles all.
            if let date = DateHelper.parseDate(from: value) {
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
            logger.log("View with Void valueType does not support setElementValueFromString: \(viewModel.elementType) for viewID: \(viewID)", .warning)
            return
        } else {
            logger.log("Unsupported valueType for setElementValueFromString: \(valueType) for viewID: \(viewID)", .warning)
            return
        }
        
        if let convertedValue {
            setElementValue(windowUUID: windowUUID, viewID: viewID, viewPartID: viewPartID, value: convertedValue)
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
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        if let existing = viewModel.states[key] {
            guard type(of: existing) == type(of: value) else {
                logger.log("Type mismatch for state key '\(key)' on viewID: \(viewID); expected \(type(of: existing)), got \(type(of: value))", .error)
                return
            }
        }
        viewModel.objectWillChange.send()
        viewModel.mutationToken &+= 1
        viewModel.states[key] = value
        windowModel.viewModels[viewID] = viewModel
        endRefreshTargeting(windowUUID: windowUUID, viewID: viewID)
        logger.log("Set state '\(key)' for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Parses a string into the type of the existing state value and stores it.
    // Uses type(of: existing) for O(1) type detection without trying every possible cast.
    // If the key does not yet exist, stores the string as-is.
    public func setElementStateFromString(windowUUID: String, viewID: Int, key: String, value: String) {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
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
        endRefreshTargeting(windowUUID: windowUUID, viewID: viewID)
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
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        viewModel.objectWillChange.send()
        viewModel.states["content"] = rows
        if let selectedRow = viewModel.value as? [String], !rows.contains(where: { $0.first == selectedRow.first }) {
            viewModel.value = [] as [String]
        }
        windowModel.viewModels[viewID] = viewModel
        endRefreshTargeting(windowUUID: windowUUID, viewID: viewID)
        logger.log("Set \(rows.count) rows for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Clears all content rows from a table/list view element, preserving column definitions.
    public func clearElementRows(windowUUID: String, viewID: Int) {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        viewModel.objectWillChange.send()
        viewModel.states["content"] = [] as [[String]]
        if viewModel.value is [String] {
            viewModel.value = [] as [String]
        }
        windowModel.viewModels[viewID] = viewModel
        endRefreshTargeting(windowUUID: windowUUID, viewID: viewID)
        logger.log("Cleared table rows for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Appends rows to a table/list view element's existing content.
    public func appendElementRows(windowUUID: String, viewID: Int, rows: [[String]]) {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        viewModel.objectWillChange.send()
        let existingContent = viewModel.states["content"] as? [[String]] ?? []
        viewModel.states["content"] = existingContent + rows
        windowModel.viewModels[viewID] = viewModel
        endRefreshTargeting(windowUUID: windowUUID, viewID: viewID)
        logger.log("Appended \(rows.count) rows to table viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // MARK: - Element Selection API
    //
    // Programmatic row selection for content-backed Table and List elements. Selection is stored in
    // the element's `value` ([String] = the selected row's column values); the SwiftUI selection
    // binding's getter finds the content row equal to `value`. These methods set `value` to the
    // chosen content row WITHOUT replacing the rows — distinct from setElementValue([String]),
    // which is interpreted as new list content.
    //
    // These do NOT fire the element's actionID: programmatic selection is silent to avoid
    // selection-changed handler feedback loops. Read the result back via getElementValue.
    // They apply to Table, homogeneous List, and template List (all backed by states["content"]);
    // they do not apply to heterogeneous List children, which select by child element ID.

    // Selects a row by its 0-based index in the element's content rows.
    // An index outside 0..<rowCount clears the selection.
    // Returns the selected row's column values, or nil if the view is not a Table/List or the
    // index was out of range (selection cleared).
    @discardableResult
    public func selectElementRow(windowUUID: String, viewID: Int, index: Int) -> [String]? {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("selectElementRow: no view for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        guard let content = viewModel.states["content"] as? [[String]] else {
            logger.log("selectElementRow: viewID \(viewID) is not a Table/List (no row content)", .warning)
            return nil
        }
        guard content.indices.contains(index) else {
            logger.log("selectElementRow: index \(index) out of range (0..<\(content.count)) for viewID: \(viewID); clearing selection", .debug)
            clearElementSelection(windowUUID: windowUUID, viewID: viewID)
            return nil
        }
        let rowValues = content[index]
        guard (viewModel.value as? [String]) != rowValues else { return rowValues }
        viewModel.objectWillChange.send()
        viewModel.mutationToken &+= 1
        viewModel.value = rowValues
        windowModel.viewModels[viewID] = viewModel
        logger.log("Selected row \(index) for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
        return rowValues
    }

    // Selects the first row whose column value matches `text`.
    // When `column` is nil, matches a row in which ANY column equals `text`; otherwise matches the
    // given 0-based column only. Matching is exact, case-sensitive string equality.
    // Returns the 0-based index of the selected row, or nil if no row matched (selection unchanged).
    @discardableResult
    public func selectElementRow(windowUUID: String, viewID: Int, matching text: String, column: Int? = nil) -> Int? {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("selectElementRow(matching:): no view for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return nil
        }
        guard let content = viewModel.states["content"] as? [[String]] else {
            logger.log("selectElementRow(matching:): viewID \(viewID) is not a Table/List (no row content)", .warning)
            return nil
        }
        let matchIndex = content.firstIndex { row in
            if let column {
                return column >= 0 && column < row.count && row[column] == text
            }
            return row.contains(text)
        }
        guard let idx = matchIndex else {
            let where_ = column.map { " in column \($0)" } ?? ""
            logger.log("selectElementRow(matching:): no row matches '\(text)'\(where_) for viewID: \(viewID)", .debug)
            return nil
        }
        _ = selectElementRow(windowUUID: windowUUID, viewID: viewID, index: idx)
        return idx
    }

    // Clears the current selection of a Table or List element (no-op if nothing is selected).
    public func clearElementSelection(windowUUID: String, viewID: Int) {
        guard let windowModel = windowModels[windowUUID],
              let viewModel = windowModel.viewModels[viewID] else {
            logger.log("clearElementSelection: no view for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        guard let selected = viewModel.value as? [String] else {
            logger.log("clearElementSelection: viewID \(viewID) is not a Table/List", .warning)
            return
        }
        guard !selected.isEmpty else { return }
        viewModel.objectWillChange.send()
        viewModel.mutationToken &+= 1
        viewModel.value = [] as [String]
        windowModel.viewModels[viewID] = viewModel
        logger.log("Cleared selection for viewID: \(viewID), windowUUID: \(windowUUID)", .debug)
    }

    // Returns a dictionary mapping positive (user-assigned) view IDs to their view type strings for a given window.
    // Negative IDs are auto-assigned and excluded; 0 is not a valid ID.
    // Includes elements loaded dynamically by LoadableView (merged into viewModels but not in the element tree).
    public func getElementInfo(windowUUID: String) -> [Int: String] {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("No window found for windowUUID: \(windowUUID)", .warning)
            return [:]
        }
        var result: [Int: String] = [:]
        if let rootElement = windowModel.element {
            collectElementInfo(from: rootElement, into: &result)
        }
        // Also include positive IDs from viewModels that weren't in the element tree
        // (e.g. elements loaded dynamically by LoadableView)
        for (id, viewModel) in windowModel.viewModels {
            if id > 0 && result[id] == nil {
                result[id] = viewModel.elementType
            }
        }
        return result
    }

    // Recursively collects element IDs and types from the element tree
    private func collectElementInfo(from element: any ActionUIElementBase, into result: inout [Int: String]) {
        if element.id > 0 {
            result[element.id] = element.type
        }
        for child in element.childElements {
            collectElementInfo(from: child, into: &result)
        }
    }

    // MARK: - Window-Level Modal (sheet / fullScreenCover)

    /// Load JSON or plist data and present it as a sheet or full-screen cover in the specified window.
    /// ViewModels for the modal content are registered in the window's pool and cleaned up on dismiss.
    public func presentModal(
        windowUUID: String,
        data: Data,
        format: String,
        style: ModalStyle,
        onDismissActionID: String? = nil
    ) throws {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("presentModal: No WindowModel for windowUUID: \(windowUUID)", .error)
            throw NSError(domain: "ActionUIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No WindowModel for windowUUID"])
        }
        let element = try windowModel.loadModalDescription(from: data, format: format)
        let loadedIDs = collectAllElementIDs(from: element)
        windowModel.windowModal = WindowModal(
            element: element,
            style: style,
            onDismissActionID: onDismissActionID,
            loadedViewIDs: loadedIDs
        )
        logger.log("presentModal: presenting \(style) for windowUUID: \(windowUUID)", .debug)
    }

    /// Dismiss the active sheet or fullScreenCover, remove its ViewModels, and fire onDismissActionID if set.
    public func dismissModal(windowUUID: String) {
        guard let windowModel = windowModels[windowUUID],
              let modal = windowModel.windowModal else { return }
        var updated = windowModel.viewModels
        for id in modal.loadedViewIDs { updated.removeValue(forKey: id) }
        windowModel.viewModels = updated
        windowModel.windowModal = nil
        if let actionID = modal.onDismissActionID {
            actionHandler(actionID, windowUUID: windowUUID, viewID: 0, viewPartID: 0)
        }
        logger.log("dismissModal: windowUUID: \(windowUUID)", .debug)
    }

    // MARK: - Window-Level Dialog (alert / confirmationDialog)

    /// Present a system alert attached to the window.
    public func presentAlert(
        windowUUID: String,
        title: String,
        message: String? = nil,
        buttons: [DialogButton] = [DialogButton(title: "OK", role: .cancel, actionID: nil)]
    ) {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("presentAlert: No WindowModel for windowUUID: \(windowUUID)", .error)
            return
        }
        windowModel.windowDialog = WindowDialog(style: .alert, title: title, message: message, buttons: buttons)
        logger.log("presentAlert: '\(title)' for windowUUID: \(windowUUID)", .debug)
    }

    /// Present a confirmation dialog (action sheet on iOS) attached to the window.
    public func presentConfirmationDialog(
        windowUUID: String,
        title: String,
        message: String? = nil,
        buttons: [DialogButton]
    ) {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("presentConfirmationDialog: No WindowModel for windowUUID: \(windowUUID)", .error)
            return
        }
        windowModel.windowDialog = WindowDialog(style: .confirmationDialog, title: title, message: message, buttons: buttons)
        logger.log("presentConfirmationDialog: '\(title)' for windowUUID: \(windowUUID)", .debug)
    }

    /// Dismiss the active alert or confirmationDialog without firing any action.
    /// Normally SwiftUI calls this automatically via the binding when any button is tapped.
    public func dismissDialog(windowUUID: String) {
        guard let windowModel = windowModels[windowUUID] else { return }
        windowModel.windowDialog = nil
        logger.log("dismissDialog: windowUUID: \(windowUUID)", .debug)
    }

    // MARK: - Window-Level Toast (snackbar)

    /// Present a transient, auto-dismissing toast pinned above content. If a toast is already
    /// visible, the new one is queued and shown after the current dismisses (coalesces rapid posts).
    /// Pass actionTitle + actionID together to add one inline action button (e.g. "Undo").
    public func presentToast(
        windowUUID: String,
        message: String,
        duration: TimeInterval = 4.0,
        actionTitle: String? = nil,
        actionID: String? = nil
    ) {
        guard let windowModel = windowModels[windowUUID] else {
            logger.log("presentToast: No WindowModel for windowUUID: \(windowUUID)", .error)
            return
        }
        var action: ToastAction? = nil
        if let actionTitle, let actionID {
            action = ToastAction(title: actionTitle, actionID: actionID)
        }
        let toast = WindowToast(message: message, duration: duration, action: action)
        if windowModel.windowToast == nil {
            windowModel.windowToast = toast
        } else {
            windowModel.toastQueue.append(toast)
        }
        logger.log("presentToast: '\(message)' for windowUUID: \(windowUUID)", .debug)
    }

    /// Dismiss the current toast. If more toasts are queued, the next one is shown.
    /// Normally called by the toast view's auto-dismiss timer or its inline action button.
    public func dismissToast(windowUUID: String) {
        guard let windowModel = windowModels[windowUUID] else { return }
        if windowModel.toastQueue.isEmpty {
            windowModel.windowToast = nil
        } else {
            windowModel.windowToast = windowModel.toastQueue.removeFirst()
        }
        logger.log("dismissToast: windowUUID: \(windowUUID)", .debug)
    }

    // Recursively collect all element IDs from an element tree (used for modal ViewModel cleanup).
    private func collectAllElementIDs(from element: any ActionUIElementBase) -> Set<Int> {
        var ids: Set<Int> = [element.id]
        for child in element.childElements {
            ids.formUnion(collectAllElementIDs(from: child))
        }
        return ids
    }

    // MARK: - Runtime structural mutations (insert / remove)

    // Inserts an element into a flat container ("children" / "destinations" / etc.)
    // of the parent identified by parentID. If `container` is omitted and the parent has exactly
    // one flat container, that container is used; otherwise an InsertError.containerRequired is thrown.
    // Returns the inserted element's id.
    public func insertElement(
        windowUUID: String,
        parentID: Int,
        dict: [String: Any],
        container: String? = nil,
        position: InsertPosition = .append
    ) throws -> Int {
        guard let windowModel = windowModels[windowUUID] else {
            throw InsertError.windowNotFound(windowUUID)
        }
        let resolvedContainer = try resolveContainer(parentID: parentID, windowModel: windowModel, requestedContainer: container, expectedShape: .flat)
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: logger)
        let filteredDict = filter.filter(dict) as? [String: Any] ?? dict
        let newElement = try ActionUIElement(from: filteredDict, logger: logger)
        return try windowModel.insertElement(newElement, parentID: parentID, container: resolvedContainer, position: position)
    }

    // JSON-string convenience wrapper around insertElement(dict:).
    public func insertElement(
        windowUUID: String,
        parentID: Int,
        json: String,
        container: String? = nil,
        position: InsertPosition = .append
    ) throws -> Int {
        guard let data = json.data(using: .utf8) else {
            throw InsertError.invalidJSON("Could not encode JSON string as UTF-8")
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw InsertError.invalidJSON("\(error)")
        }
        guard let dict = parsed as? [String: Any] else {
            throw InsertError.invalidJSON("Expected JSON object describing one element")
        }
        return try insertElement(windowUUID: windowUUID, parentID: parentID, dict: dict, container: container, position: position)
    }

    // Inserts a row of cells into a Grid-style `rows` container. `cells` is the array of cell
    // element dictionaries. Rows have no synthetic identity — `position` may not be
    // .before/.after; use .append, .prepend, or .at(_:). Returns the inserted cells' ids.
    public func insertRow(
        windowUUID: String,
        parentID: Int,
        cells: [[String: Any]],
        container: String? = nil,
        position: InsertPosition = .append
    ) throws -> [Int] {
        guard let windowModel = windowModels[windowUUID] else {
            throw InsertError.windowNotFound(windowUUID)
        }
        let resolvedContainer = try resolveContainer(parentID: parentID, windowModel: windowModel, requestedContainer: container, expectedShape: .rows)
        let filter = PlatformFilter(active: PlatformFilter.runtimeActiveSet, logger: logger)
        let elements = try cells.map { cell -> ActionUIElement in
            let filteredCell = filter.filter(cell) as? [String: Any] ?? cell
            return try ActionUIElement(from: filteredCell, logger: logger)
        }
        return try windowModel.insertRow(elements, parentID: parentID, container: resolvedContainer, position: position)
    }

    // JSON-string convenience wrapper around insertRow(cells:). The JSON must encode an
    // array of cell objects, e.g. `[{"type":"Text",...}, {"type":"Button",...}]`.
    public func insertRow(
        windowUUID: String,
        parentID: Int,
        json: String,
        container: String? = nil,
        position: InsertPosition = .append
    ) throws -> [Int] {
        guard let data = json.data(using: .utf8) else {
            throw InsertError.invalidJSON("Could not encode JSON string as UTF-8")
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw InsertError.invalidJSON("\(error)")
        }
        guard let arr = parsed as? [[String: Any]] else {
            throw InsertError.invalidJSON("Expected JSON array of cell objects")
        }
        return try insertRow(windowUUID: windowUUID, parentID: parentID, cells: arr, container: container, position: position)
    }

    // Removes the element with viewID from its parent. Refuses to remove the window's root
    // element. Cascade-removes ViewModels for all descendants.
    //
    // Note on Grid rows: only individual cells (which carry ids) are addressable. A whole
    // row has no synthetic id and therefore cannot be removed via this method — remove
    // each cell, or rebuild the parent.
    public func removeElement(windowUUID: String, viewID: Int) throws {
        guard let windowModel = windowModels[windowUUID] else {
            throw InsertError.windowNotFound(windowUUID)
        }
        try windowModel.removeElement(viewID: viewID)
    }

    // Resolves which insertable container to use given the parent's element type and the
    // requested container (or nil). Validates the container's shape matches what the caller's
    // method expects (flat for insertElement, rows for insertRow).
    private func resolveContainer(parentID: Int, windowModel: WindowModel, requestedContainer: String?, expectedShape: ContainerShape) throws -> String {
        guard let parentVM = windowModel.viewModels[parentID] else {
            throw InsertError.parentNotFound(parentID: parentID)
        }
        
        guard let containers = ActionUIRegistry.shared.getInsertableContainers(forElementType: parentVM.elementType) else {
            throw InsertError.notAContainer(type: parentVM.elementType)
        }

        if let requested = requestedContainer {
            guard let shape = containers[requested] else {
                throw InsertError.unknownContainer(container: requested, vaildContainers: Array(containers.keys).sorted())
            }
            if shape != expectedShape {
                let methodName = expectedShape == .flat ? "insertElement" : "insertRow"
                let altMethod = expectedShape == .flat ? "insertRow" : "insertElement"
                throw InsertError.wrongMethod(container: requested, expectedShape: shape,
                    message: "\(methodName) requires a \(expectedShape) container — use \(altMethod) for this container.")
            }
            return requested
        }

        // Auto-derive: pick the unique container matching the expected shape.
        let matching = containers.filter { $0.value == expectedShape }.map { $0.key }
        if matching.count == 1 { return matching[0] }
        throw InsertError.containerRequired(vaildContainers: matching.sorted())
    }

    // Sets a property value for a view and re-validates it
    // Design decision: Re-validates using ActionUIRegistry to ensure type safety and HIG compliance (e.g., 'disabled' must be Bool)
    // Updates validatedProperties to preserve runtime mutations and trigger SwiftUI refresh via viewModels
    public func setElementProperty(windowUUID: String, viewID: Int, propertyName: String, value: Any) {
        guard let viewModel = windowModels[windowUUID]?.viewModels[viewID] else {
            logger.log("No view found for windowUUID: \(windowUUID), viewID: \(viewID)", .warning)
            return
        }
        // Notify SwiftUI before mutating the non-published validatedProperties,
        // matching the willSet contract expected by ObservableObject observers.
        viewModel.objectWillChange.send()
        viewModel.mutationToken &+= 1
        viewModel.validatedProperties[propertyName] = value
        // Re-validate to ensure type safety and HIG compliance
        viewModel.validateProperties(viewModel.validatedProperties, elementType: viewModel.elementType, logger: logger)
        logger.log("Set property '\(propertyName)' to \(value) for viewID: \(viewID)", .debug)
    }
}
