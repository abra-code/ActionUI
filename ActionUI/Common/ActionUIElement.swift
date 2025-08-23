// Sources/ActionUIElement.swift
/*
 Sample JSON for ActionUIElement (base structure for all elements):
 {
   "type": "View",       // Matches the view class name (e.g., "NavigationStack", "NavigationLink", "NavigationSplitView")
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},     // Optional: Dictionary of view-specific properties
   "children": [],       // Optional: Array of child elements
   "rows": [             // Optional: Array of arrays of child elements (for Grid). Note: Handled as a top-level key in JSON but stored in properties["rows"].
     [
       { "type": "Text", "properties": { "text": "Cell1" } },
       { "type": "Button", "properties": { "title": "Click" } }
     ]
   ],
   "content": {          // Optional: Single child view (for NavigationStack, etc.). Note: Handled as a top-level key in JSON but stored in properties["content"].
     "type": "Text", "properties": { "text": "Home" }
   },
   "destination": {      // Optional: Single child view (for NavigationLink). Note: Handled as a top-level key in JSON but stored in properties["destination"].
     "type": "Text", "properties": { "text": "Detail" }
   },
   "sidebar": {          // Optional: Single child view (for NavigationSplitView). Note: Handled as a top-level key in JSON but stored in properties["sidebar"].
     "type": "Text", "properties": { "text": "Sidebar" }
   },
   "detail": {           // Optional: Single child view (for NavigationSplitView). Note: Handled as a top-level key in JSON but stored in properties["detail"].
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
    var children: [any ActionUIElement]? { get }
}

// Protocol for constructing SwiftUI views from ActionUI elements
protocol ActionUIViewConstruction {
    static var valueType: Any.Type { get }
    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] { get }
    static var buildView: ((any ActionUIElement, Binding<[Int: Any]>, String, [String: Any], any ActionUILogger) -> any SwiftUI.View) { get }
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View { get }
}

// Default implementations for ActionUIViewConstruction
extension ActionUIViewConstruction {
    static var valueType: Any.Type {
        return Void.self
    }
    
    static var applyModifiers: (any SwiftUI.View, [String: Any], any ActionUILogger) -> any SwiftUI.View {
        return { view, _, _ in view }
    }
}

// Concrete implementation of ActionUIElement for static UI elements
struct StaticElement: ActionUIElement {
    let id: Int
    let type: String
    let properties: [String: Any]
    let children: [any ActionUIElement]?
    
    // Counter for generating unique negative IDs when not specified
    private static var negativeIDCounter: Int = -1
    
    // Generates a unique negative ID for elements without an explicit ID
    internal static func generateNegativeID() -> Int {
        defer { negativeIDCounter -= 1 }
        return negativeIDCounter
    }
    
    // Initializes a StaticElement with explicit values
    init(id: Int, type: String, properties: [String: Any], children: [any ActionUIElement]?) {
        self.id = id
        self.type = type
        self.properties = properties
        self.children = children
    }
    
    // Codable conformance for encoding
    enum CodingKeys: String, CodingKey {
        case id, type, properties, children, rows, content, destination, sidebar, detail
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        let decodedProperties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties) ?? [:]
        properties = decodedProperties.mapValues { $0.value }
        let decodedChildren = try container.decodeIfPresent([AnyCodable].self, forKey: .children)
        children = decodedChildren?.compactMap { $0.value as? any ActionUIElement }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        let encodableProperties = try properties.mapValues { try AnyCodable.convertAnyToAnyCodable($0) }
        try container.encodeIfPresent(encodableProperties, forKey: .properties)
        if let children = children {
            let encodableChildren = children.map { AnyCodable($0) }
            try container.encodeIfPresent(encodableChildren, forKey: .children)
        } else {
            try container.encodeNil(forKey: .children)
        }
        // Encode component-specific keys as top-level if present in properties
        for key in ["rows", "content", "destination", "sidebar", "detail"] {
            if let value = properties[key] as? [any ActionUIElement] {
                let encodableValue = value.map { AnyCodable($0) }
                try container.encodeIfPresent(encodableValue, forKey: CodingKeys(rawValue: key)!)
            } else if let value = properties[key] as? [[any ActionUIElement]] {
                let encodableValue = value.map { row in row.map { AnyCodable($0) } }
                try container.encodeIfPresent(encodableValue, forKey: CodingKeys(rawValue: key)!)
            } else if let value = properties[key] as? any ActionUIElement {
                try container.encodeIfPresent(AnyCodable(value), forKey: CodingKeys(rawValue: key)!)
            }
        }
    }
    
    // Initializes a StaticElement from a dictionary (e.g., parsed JSON)
    init(from dictionary: [String: Any]) throws {
        let id = dictionary["id"] as? Int ?? StaticElement.generateNegativeID()
        guard let type = dictionary["type"] as? String else {
            throw NSError(domain: "StaticElement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing type"])
        }
        let properties = dictionary["properties"] as? [String: Any] ?? [:]
        let childrenArray = dictionary["children"] as? [[String: Any]]
        let children = try childrenArray?.map { try StaticElement(from: $0) }
        
        var updatedProperties = properties
        
        // Decode rows for Grid
        // Note: JSON specifies "rows" as a top-level key, but we move it to properties["rows"] to align with existing Grid code expecting rows in properties.
        if let rowsArray = dictionary["rows"] as? [[[String: Any]]] {
            let rows = try rowsArray.map { row in
                try row.map { try StaticElement(from: $0) }
            }
            updatedProperties["rows"] = rows
        }
        
        // Decode single child views for navigation components
        // Note: JSON specifies "content", "destination", "sidebar", "detail" as top-level keys, but we move them to properties for compatibility with existing component code.
        for key in ["content", "destination", "sidebar", "detail"] {
            if let childDict = dictionary[key] as? [String: Any] {
                do {
                    let childElement = try StaticElement(from: childDict)
                    updatedProperties[key] = childElement
                } catch {
                    // Log error and skip invalid child, leaving property unset
                    // ActionUILogger.shared.log("Failed to parse \(key) element: \(error)", .error)
                    print("Error: Failed to parse \(key) element: \(error)")
                }
            }
        }
        
        self.init(id: id, type: type, properties: updatedProperties, children: children)
    }
}

// Extension to make StaticElement Equatable
extension StaticElement: Equatable {
    static func == (lhs: StaticElement, rhs: StaticElement) -> Bool {
        guard lhs.id == rhs.id,
              lhs.type == rhs.type,
              PropertyComparison.arePropertiesEqual(lhs.properties, rhs.properties) else {
            return false
        }
        if let lhsChildren = lhs.children, let rhsChildren = rhs.children {
            guard lhsChildren.count == rhsChildren.count else { return false }
            return zip(lhsChildren, rhsChildren).allSatisfy { $0 as? StaticElement == $1 as? StaticElement }
        }
        return lhs.children == nil && rhs.children == nil
    }
}
