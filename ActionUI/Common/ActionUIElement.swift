// Sources/ActionUIElement.swift
/*
 Sample JSON for ActionUIElement (base structure for all elements):
 {
   "type": "View",       // Matches the view class name (e.g., "NavigationStack", "NavigationLink", "NavigationSplitView")
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
   }
 }
*/

import SwiftUI
import Foundation

// Protocol defining the structure of an ActionUIElement, used for JSON-based UI construction
protocol ActionUIElement: Identifiable, Codable {
    var id: Int { get }
    var type: String { get }
    var properties: [String: Any] { get }
    var subviews: [String: Any]? { get } // optional dictionary with "children", "rows", "content", "destination", "sidebar" or "detail"
}

// Protocol for constructing SwiftUI views from ActionUIElements
@MainActor
protocol ActionUIViewConstruction {
    static var valueType: Any.Type { get }
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] { get }
    static var buildView: ((any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View) { get }
    static var applyModifiers: (any SwiftUI.View, any ActionUIElement, String, [String: Any], any ActionUILogger) -> any SwiftUI.View { get }
    static var initialValue: (ViewModel) -> Any? { get }
}

// Default implementations for ActionUIViewConstruction
extension ActionUIViewConstruction {
    static var valueType: Any.Type {
        return Void.self
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElement, String, [String: Any], any ActionUILogger) -> any SwiftUI.View {
        return { view, _, _, _, _ in view }
    }
    
    static var initialValue: (ViewModel) -> Any?
    {
        return { model in return model.value }
    }
}

// Concrete implementation of ActionUIElement with data for constructing SwiftUI views
struct ViewElement: ActionUIElement {
    let id: Int
    let type: String
    let properties: [String: Any]
    var subviews: [String: Any]?
    
    // Counter for generating unique negative IDs when not specified
    private static var negativeIDCounter: Int = -1
    
    // Generates a unique negative ID for elements without an explicit ID
    internal static func generateNegativeID() -> Int {
        defer { negativeIDCounter -= 1 }
        return negativeIDCounter
    }
    
    // Initializes a ViewElement with explicit values
    init(id: Int, type: String, properties: [String: Any], subviews: [String: Any]?) {
        self.id = id
        self.type = type
        self.properties = properties
        self.subviews = subviews
    }
    
    // Codable conformance for encoding
    enum ElementCodingKeys: String, CodingKey {
        case id, type, properties, children, rows, content, destination, sidebar, detail
    }
    
    init(from decoder: Decoder) throws {
        let logger = decoder.logger
        let container = try decoder.container(keyedBy: ElementCodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? ViewElement.generateNegativeID()
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
        if let children = try container.decodeIfPresent([ViewElement].self, forKey: .children) {
            if subviews == nil { subviews = [:] }
            subviews!["children"] = children
        }
        
        if let rows = try container.decodeIfPresent([[ViewElement]].self, forKey: .rows) {
            if subviews == nil { subviews = [:] }
            subviews!["rows"] = rows
        }
        
        for key in ["content", "destination", "sidebar", "detail"] {
            if let child = try container.decodeIfPresent(ViewElement.self, forKey: ElementCodingKeys(rawValue: key)!) {
                if subviews == nil { subviews = [:] }
                subviews![key] = child
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
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
            return
        }
        
        // Encode children
        if let children = subviews["children"] as? [ViewElement] {
            try container.encodeIfPresent(children, forKey: .children)
        } else {
            try container.encodeNil(forKey: .children)
        }
        
        // Encode rows
        if let rows = subviews["rows"] as? [[ViewElement]] {
            try container.encodeIfPresent(rows, forKey: .rows)
        } else {
            try container.encodeNil(forKey: .rows)
        }
        
        // Encode single child views
        for key in ["content", "destination", "sidebar", "detail"] {
            if let child = subviews[key] as? ViewElement {
                try container.encodeIfPresent(child, forKey: ElementCodingKeys(rawValue: key)!)
            } else {
                try container.encodeNil(forKey: ElementCodingKeys(rawValue: key)!)
            }
        }
    }
    
    // Initializes a ViewElement from a dictionary (e.g., parsed JSON)
    init(from dictionary: [String: Any], logger: any ActionUILogger) throws {
        let id = dictionary["id"] as? Int ?? ViewElement.generateNegativeID()
        guard let type = dictionary["type"] as? String else {
            throw NSError(domain: "ViewElement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing type"])
        }
        let properties = dictionary["properties"] as? [String: Any] ?? [:]
        let childrenArray = dictionary["children"] as? [[String: Any]]
        // Note: JSON specifies "children" as a top-level key, but we move it to subviews["children"]
        let children = try childrenArray?.map { try ViewElement(from: $0, logger: logger) }
        var subviews: [String: Any]?
        if children != nil {
            subviews = [:]
            subviews!["children"] = children
        }
                
        // Decode rows for Grid
        // Note: JSON specifies "rows" as a top-level key, but we move it to subviews["rows"]
        if let rowsArray = dictionary["rows"] as? [[[String: Any]]] {
            let rows = try rowsArray.map { row in
                try row.map { try ViewElement(from: $0, logger: logger) }
            }
            
            if subviews == nil {
                subviews = [:]
            }
            subviews!["rows"] = rows
        }
        
        // Decode single child views for navigation components
        // Note: JSON specifies "content", "destination", "sidebar", "detail" as top-level keys, but we move them to subviews
        for key in ["content", "destination", "sidebar", "detail"] {
            if let childDict = dictionary[key] as? [String: Any] {
                do {
                    let childElement = try ViewElement(from: childDict, logger: logger)
                    if subviews == nil {
                        subviews = [:]
                    }
                    subviews![key] = childElement
                } catch {
                    // Log error and skip invalid child, leaving property unset
                    logger.log("Failed to parse \(key) element: \(error)", .error)
                }
            }
        }
        
        self.init(id: id, type: type, properties: properties, subviews: subviews)
    }
}

// Extension to make ViewElement Equatable
extension ViewElement: Equatable {
    static func == (lhs: ViewElement, rhs: ViewElement) -> Bool {
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
        for key in ["children", "rows", "content", "destination", "sidebar", "detail"] {
            let lhsValue = lhsSubviews[key]
            let rhsValue = rhsSubviews[key]
            
            switch (lhsValue, rhsValue) {
            case (nil, nil):
                continue
            case (let lhsChildren as [ViewElement], let rhsChildren as [ViewElement]):
                guard lhsChildren.count == rhsChildren.count,
                      zip(lhsChildren, rhsChildren).allSatisfy({ $0 == $1 }) else {
                    return false
                }
            case (let lhsRows as [[ViewElement]], let rhsRows as [[ViewElement]]):
                guard lhsRows.count == rhsRows.count,
                      zip(lhsRows, rhsRows).allSatisfy({ zip($0, $1).allSatisfy({ $0 == $1 }) }) else {
                    return false
                }
            case (let lhsChild as ViewElement, let rhsChild as ViewElement):
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
extension ActionUIElement {
    func findElement(by viewID: Int) -> (any ActionUIElement)? {
        // Check if the current element matches the ID
        if self.id == viewID {
            return self
        }
        
        // Check all possible subview keys, if any
        guard let subviews, !subviews.isEmpty else {
            return nil
        }
        
        // Search in "children" (array of elements)
        if let children = subviews["children"] as? [any ActionUIElement] {
            for child in children {
                if let found = child.findElement(by: viewID) {
                    return found
                }
            }
        }
        
        // Search in "rows" (array of arrays of elements)
        if let rows = subviews["rows"] as? [[any ActionUIElement]] {
            for row in rows {
                for child in row {
                    if let found = child.findElement(by: viewID) {
                        return found
                    }
                }
            }
        }
        
        // Search in single-child keys: "content", "destination", "sidebar", "detail"
        if let content = subviews["content"] as? any ActionUIElement,
           let found = content.findElement(by: viewID) {
            return found
        }
        if let destination = subviews["destination"] as? any ActionUIElement,
           let found = destination.findElement(by: viewID) {
            return found
        }
        if let sidebar = subviews["sidebar"] as? any ActionUIElement,
           let found = sidebar.findElement(by: viewID) {
            return found
        }
        if let detail = subviews["detail"] as? any ActionUIElement,
           let found = detail.findElement(by: viewID) {
            return found
        }
        return nil
    }
}
