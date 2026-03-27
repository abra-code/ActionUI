// Sources/ActionUIElement.swift
/*
 Sample JSON for ActionUIElementBase (base structure for all elements):
 {
   "type": "View",       // Matches the SwiftUI view or other element class name (e.g., "NavigationStack", "NavigationLink", "NavigationSplitView")
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},     // Optional: Dictionary of view-specific properties
   "children": [],       // Optional: Array of child elements. Note: Handled as a top-level key in JSON but stored in subviews["children"]
   "rows": [             // Optional: Array of arrays of child elements (for Grid). Note: Handled as a top-level key in JSON but stored in subviews["rows"]
     [
       { "type": "Text", "properties": { "text": "Cell1" } },
       { "type": "Button", "properties": { "title": "Click" } }
     ]
   ],
   "content": {          // Optional: Single child view (for NavigationStack, etc.). Note: Handled as a top-level key in JSON but stored in subviews["content"]
     "type": "Text", "properties": { "text": "Home" }
   },
   "destination": {      // Optional: Single child view (for NavigationLink). Note: Handled as a top-level key in JSON but stored in subviews["destination"]
     "type": "Text", "properties": { "text": "Detail" }
   },
   "sidebar": {          // Optional: Single child view (for NavigationSplitView). Note: Handled as a top-level key in JSON but stored in subviews["sidebar"]
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "detail": {           // Optional: Single child view (for NavigationSplitView). Note: Handled as a top-level key in JSON but stored in subviews["detail"]
     "type": "Text", "properties": { "text": "Detail" }
   },
   "label": {           // Optional: Single child view (for Menu). Note: Handled as a top-level key in JSON but stored in subviews["label"]
     "type": "Image", "properties": { "systemName": "ellipsis.circle" }
   },
   "popover": {          // Optional: Single child view for popover content (attachable to any view). Note: Handled as a top-level key in JSON but stored in subviews["popover"]
     "type": "Text", "properties": { "text": "Popover content" }
   },
   "destinations": []    // Optional: Array of destination elements to switch on their id in NavigationStack & NavigationSplitView detail pane. Note: Handled as a top-level key in JSON but stored in subviews["destinations"]
   "commands": [],       // Optional: Array of command elements. Note: Handled as a top-level key in JSON but stored in subviews["commands"]
 }
*/

import SwiftUI
import Foundation

// Protocol defining the structure of an ActionUIElementBase, used for JSON-based UI construction
public protocol ActionUIElementBase: Identifiable, Codable {
    var id: Int { get }
    var type: String { get }
    var properties: [String: Any] { get }
    var subviews: [String: Any]? { get } // optional dictionary with "children", "rows", "content", "destination", "sidebar", "detail", "label", "popover", "destinations"
}

protocol ActionUIPropertyValidation {
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] { get }
}

// Protocol for constructing SwiftUI views from ActionUIElements
@MainActor
protocol ActionUIViewConstruction : ActionUIPropertyValidation {
    static var valueType: Any.Type { get }
    static var buildView: ((any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View) { get }
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View { get }
    static var initialValue: (ViewModel) -> Any? { get }
    static var initialStates: (ViewModel) -> [String: Any] { get }
}


// Concrete implementation of ActionUIElementBase with data for constructing SwiftUI views and other elements
public struct ActionUIElement: ActionUIElementBase {
    public let id: Int
    public let type: String
    public let properties: [String: Any]
    public var subviews: [String: Any]?
    
    // Counter for generating unique negative IDs when not specified.
    // Protected by a lock so it is safe to call from any thread (e.g. Decodable init).
    private static let negativeIDLock = NSLock()
    private static var negativeIDCounter: Int = -1

    // Generates a unique negative ID for elements without an explicit ID
    internal static func generateNegativeID() -> Int {
        negativeIDLock.withLock {
            let id = negativeIDCounter
            negativeIDCounter -= 1
            return id
        }
    }
    
    // Initializes a ActionUIElement with explicit values
    init(id: Int, type: String, properties: [String: Any], subviews: [String: Any]?) {
        self.id = id
        self.type = type
        self.properties = properties
        self.subviews = subviews
    }
    
    // Codable conformance for encoding
    enum ElementCodingKeys: String, CodingKey {
        case id, type, properties, children, rows, content, destination, sidebar, detail, label, popover, commands, destinations
    }
    
    public init(from decoder: Decoder) throws {
        let logger = decoder.logger
        let container = try decoder.container(keyedBy: ElementCodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? ActionUIElement.generateNegativeID()
        type = try container.decode(String.self, forKey: .type)
        let decodedProperties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties) ?? [:]
        var convertedProperties: [String: Any] = [:]
        for (key, value) in decodedProperties {
            do {
                convertedProperties[key] = try AnyCodable.convertAnyCodableToAny(value)
            } catch {
                logger?.log("Failed to convert property '\(key)' for type '\(type)': \(error)", .error)
            }
        }
        properties = convertedProperties
        
        // Initialize subviews if any subview keys are present
        subviews = nil // Start with nil
        for key in ["children", "destinations"] {
            if let children = try container.decodeIfPresent([ActionUIElement].self, forKey: ElementCodingKeys(rawValue: key)!) {
                if subviews == nil { subviews = [:] }
                subviews![key] = children
            }
        }
        
        if let rows = try container.decodeIfPresent([[ActionUIElement]].self, forKey: .rows) {
            if subviews == nil { subviews = [:] }
            subviews!["rows"] = rows
        }
        
        for key in ["content", "destination", "sidebar", "detail", "label", "popover"] {
            if let child = try container.decodeIfPresent(ActionUIElement.self, forKey: ElementCodingKeys(rawValue: key)!) {
                if subviews == nil { subviews = [:] }
                subviews![key] = child
            }
        }
        
        // Decode commands array for WindowGroup
        if let commandsArray = try container.decodeIfPresent([ActionUIElement].self, forKey: .commands) {
            if !commandsArray.isEmpty {
                if subviews == nil { subviews = [:] }
                subviews!["commands"] = commandsArray
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        let logger = encoder.logger
        var container = encoder.container(keyedBy: ElementCodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        var encodableProperties: [String: AnyCodable] = [:]
        for (key, value) in properties {
            do {
                encodableProperties[key] = try AnyCodable.convertAnyToAnyCodable(value)
            } catch {
                logger?.log("Failed to encode property '\(key)' for type '\(type)': \(error)", .error)
            }
        }
        try container.encodeIfPresent(encodableProperties, forKey: .properties)
        
        // Early exit if subviews is nil
        guard let subviews else {
            try container.encodeNil(forKey: .children)
            try container.encodeNil(forKey: .rows)
            try container.encodeNil(forKey: .content)
            try container.encodeNil(forKey: .destination)
            try container.encodeNil(forKey: .sidebar)
            try container.encodeNil(forKey: .detail)
            try container.encodeNil(forKey: .popover)
            return
        }
        
        // Encode children
        for key in ["children", "destinations"] {
            if let children = subviews[key] as? [ActionUIElement] {
                try container.encodeIfPresent(children, forKey: ElementCodingKeys(rawValue: key)!)
            } else {
                try container.encodeNil(forKey: ElementCodingKeys(rawValue: key)!)
            }
        }
        
        // Encode rows
        if let rows = subviews["rows"] as? [[ActionUIElement]] {
            try container.encodeIfPresent(rows, forKey: .rows)
        } else {
            try container.encodeNil(forKey: .rows)
        }
        
        // Encode single child views
        for key in ["content", "destination", "sidebar", "detail", "label", "popover"] {
            if let child = subviews[key] as? ActionUIElement {
                try container.encodeIfPresent(child, forKey: ElementCodingKeys(rawValue: key)!)
            } else {
                try container.encodeNil(forKey: ElementCodingKeys(rawValue: key)!)
            }
        }
        
        // Encode commands array
        if let commands = subviews["commands"] as? [ActionUIElement] {
            try container.encode(commands, forKey: .commands)
        } else {
            try container.encodeNil(forKey: .commands)
        }
    }
    
    // Initializes a ActionUIElement from a dictionary (e.g., parsed JSON)
    init(from dictionary: [String: Any], logger: any ActionUILogger) throws {
        let id = dictionary["id"] as? Int ?? ActionUIElement.generateNegativeID()
        guard let type = dictionary["type"] as? String else {
            throw NSError(domain: "ActionUIElement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing type"])
        }
        let properties = dictionary["properties"] as? [String: Any] ?? [:]
        var subviews: [String: Any]?
        
        for key in ["children", "destinations"] {
            let childrenArray = dictionary[key] as? [[String: Any]]
            // Note: JSON specifies "children"/"destinations" as a top-level key, but we move it to subviews["children"/"destinations"]
            let children = try childrenArray?.map { try ActionUIElement(from: $0, logger: logger) }
            if children != nil {
                if subviews == nil { subviews = [:] }
                subviews![key] = children
            }
        }
                
        // Decode rows for Grid
        // Note: JSON specifies "rows" as a top-level key, but we move it to subviews["rows"]
        if let rowsArray = dictionary["rows"] as? [[[String: Any]]] {
            let rows = try rowsArray.map { row in
                try row.map { try ActionUIElement(from: $0, logger: logger) }
            }
            
            if subviews == nil { subviews = [:] }
            subviews!["rows"] = rows
        }
        
        // Decode single child views for navigation components
        // Note: JSON specifies "content", "destination", "sidebar", "detail" as top-level keys, but we move them to subviews
        for key in ["content", "destination", "sidebar", "detail", "label", "popover"] {
            if let childDict = dictionary[key] as? [String: Any] {
                do {
                    let childElement = try ActionUIElement(from: childDict, logger: logger)
                    if subviews == nil { subviews = [:] }
                    subviews![key] = childElement
                } catch {
                    // Log error and skip invalid child, leaving property unset
                    logger.log("Failed to parse \(key) element: \(error)", .error)
                }
            }
        }
        
        let commandsArray = dictionary["commands"] as? [[String: Any]]
        // Note: JSON specifies "commands" as a top-level key, but we move it to subviews["commands"]
        let commands = try commandsArray?.map { try ActionUIElement(from: $0, logger: logger) }
        if commands != nil {
            if subviews == nil { subviews = [:] }
            subviews!["commands"] = commands
        }

        self.init(id: id, type: type, properties: properties, subviews: subviews)
    }
}

// Extension to make ActionUIElement Equatable
extension ActionUIElement: Equatable {
    public static func == (lhs: ActionUIElement, rhs: ActionUIElement) -> Bool {
        // Compare id, type, and properties
        guard lhs.id == rhs.id,
              lhs.type == rhs.type,
              PropertyComparison.arePropertiesEqual(lhs.properties, rhs.properties) else {
            return false
        }
        
        // Handle nil and empty subviews
        let lhsSubviews = lhs.subviews ?? [:]
        let rhsSubviews = rhs.subviews ?? [:]
        guard lhsSubviews.keys.sorted() == rhsSubviews.keys.sorted() else {
            return false
        }
        
        // Compare all subviews keys
        for key in ["children", "rows", "content", "destination", "sidebar", "detail", "label", "popover", "commands", "destinations"] {
            let lhsValue = lhsSubviews[key]
            let rhsValue = rhsSubviews[key]
            
            switch (lhsValue, rhsValue) {
            case (nil, nil):
                continue
            case (let lhsChildren as [ActionUIElement], let rhsChildren as [ActionUIElement]):
                guard lhsChildren.count == rhsChildren.count,
                      zip(lhsChildren, rhsChildren).allSatisfy({ $0 == $1 }) else {
                    return false
                }
            case (let lhsRows as [[ActionUIElement]], let rhsRows as [[ActionUIElement]]):
                guard lhsRows.count == rhsRows.count,
                      zip(lhsRows, rhsRows).allSatisfy({ zip($0, $1).allSatisfy({ $0 == $1 }) }) else {
                    return false
                }
            case (let lhsChild as ActionUIElement, let rhsChild as ActionUIElement):
                guard lhsChild == rhsChild else {
                    return false
                }
            case (nil, _), (_, nil):
                return false
            default:
                return false // Type mismatch or unsupported type
            }
        }
        
        return true
    }
}

// Extension to find an element by ID in the element hierarchy
// Design decision: Recursive search supports nested JSON structures, enabling validation of properties for views at any depth
extension ActionUIElementBase {
    func findElement(by viewID: Int) -> (any ActionUIElementBase)? {
        // Check if the current element matches the ID
        if self.id == viewID {
            return self
        }
        
        // Check all possible subview keys, if any
        guard let subviews, !subviews.isEmpty else {
            return nil
        }
        
        // Search in "children" (array of elements)
        if let children = subviews["children"] as? [any ActionUIElementBase] {
            for child in children {
                if let found = child.findElement(by: viewID) {
                    return found
                }
            }
        }

        // Search in "destinations" (array of elements)
        if let destinations = subviews["destinations"] as? [any ActionUIElementBase] {
            for child in destinations {
                if let found = child.findElement(by: viewID) {
                    return found
                }
            }
        }

        // Search in "rows" (array of arrays of elements)
        if let rows = subviews["rows"] as? [[any ActionUIElementBase]] {
            for row in rows {
                for child in row {
                    if let found = child.findElement(by: viewID) {
                        return found
                    }
                }
            }
        }
        
        // Search in "commands" (array of elements)
        if let commands = subviews["commands"] as? [any ActionUIElementBase] {
            for command in commands {
                if let found = command.findElement(by: viewID) {
                    return found
                }
            }
        }
        
        // Search in single-child keys: "content", "destination", "sidebar", "detail", "label", "popover"
        if let content = subviews["content"] as? any ActionUIElementBase,
           let found = content.findElement(by: viewID) {
            return found
        }
        if let destination = subviews["destination"] as? any ActionUIElementBase,
           let found = destination.findElement(by: viewID) {
            return found
        }
        if let sidebar = subviews["sidebar"] as? any ActionUIElementBase,
           let found = sidebar.findElement(by: viewID) {
            return found
        }
        if let detail = subviews["detail"] as? any ActionUIElementBase,
           let found = detail.findElement(by: viewID) {
            return found
        }
        if let detail = subviews["label"] as? any ActionUIElementBase,
           let found = detail.findElement(by: viewID) {
            return found
        }
        if let popover = subviews["popover"] as? any ActionUIElementBase,
           let found = popover.findElement(by: viewID) {
            return found
        }
        return nil
    }
}
