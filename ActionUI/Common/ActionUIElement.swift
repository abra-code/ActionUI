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
    var subviews: [String: Any]?
    
    // Counter for generating unique negative IDs when not specified
    private static var negativeIDCounter: Int = -1
    
    // Generates a unique negative ID for elements without an explicit ID
    internal static func generateNegativeID() -> Int {
        defer { negativeIDCounter -= 1 }
        return negativeIDCounter
    }
    
    // Initializes a StaticElement with explicit values
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
        let container = try decoder.container(keyedBy: ElementCodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        let decodedProperties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties) ?? [:]
        properties = decodedProperties.mapValues { $0.value }
        let decodedChildren = try container.decodeIfPresent([AnyCodable].self, forKey: .children)
        if decodedChildren != nil {
            if (subviews == nil) { subviews = [:] }
            self.subviews!["children"] = decodedChildren?.compactMap { $0.value as? any ActionUIElement }
        }
        
        let decodedRows = try container.decodeIfPresent([[AnyCodable]].self, forKey: .rows)
        if decodedRows != nil {
            if (subviews == nil) { subviews = [:] }
            self.subviews!["rows"] = decodedRows as? [[any ActionUIElement]]
        }
        
        for key in ["content", "destination", "sidebar", "detail"] {
            if let decodedContent = try container.decodeIfPresent(AnyCodable.self, forKey: ElementCodingKeys(rawValue: key)!) {
                if (subviews == nil) { subviews = [:] }
                self.subviews![key] = decodedContent as? any ActionUIElement
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementCodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        let encodableProperties = try properties.mapValues { try AnyCodable.convertAnyToAnyCodable($0) }
        try container.encodeIfPresent(encodableProperties, forKey: .properties)
        if let children = subviews?["children"] as? [any ActionUIElement] {
            let encodableChildren = children.map { AnyCodable($0) }
            try container.encodeIfPresent(encodableChildren, forKey: .children)
        } else {
            try container.encodeNil(forKey: .children)
        }
        
        guard let subviews else {
            return
        }
        
        // Encode component-specific keys as top-level if present in properties
        for key in ["children", "rows", "content", "destination", "sidebar", "detail"] {
            if let anySubview = subviews[key] {
                if let value = anySubview as? [any ActionUIElement] {
                    let encodableValue = value.map { AnyCodable($0) }
                    try container.encodeIfPresent(encodableValue, forKey: ElementCodingKeys(rawValue: key)!)
                } else if let value = anySubview as? [[any ActionUIElement]] {
                    let encodableValue = value.map { row in row.map { AnyCodable($0) } }
                    try container.encodeIfPresent(encodableValue, forKey: ElementCodingKeys(rawValue: key)!)
                } else if let value = anySubview as? any ActionUIElement {
                    try container.encodeIfPresent(AnyCodable(value), forKey: ElementCodingKeys(rawValue: key)!)
                }
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
        // Note: JSON specifies "children" as a top-level key, but we move it to subviews["children"]
        let children = try childrenArray?.map { try StaticElement(from: $0) }
        var subviews: [String: Any]?
        if children != nil {
            subviews = [:]
            subviews!["children"] = children
        }
                
        // Decode rows for Grid
        // Note: JSON specifies "rows" as a top-level key, but we move it to subviews["rows"]
        if let rowsArray = dictionary["rows"] as? [[[String: Any]]] {
            let rows = try rowsArray.map { row in
                try row.map { try StaticElement(from: $0) }
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
                    let childElement = try StaticElement(from: childDict)
                    if subviews == nil {
                        subviews = [:]
                    }
                    subviews![key] = childElement
                } catch {
                    // Log error and skip invalid child, leaving property unset
                    // ActionUILogger.shared.log("Failed to parse \(key) element: \(error)", .error)
                    print("Error: Failed to parse \(key) element: \(error)")
                }
            }
        }
        
        self.init(id: id, type: type, properties: properties, subviews: subviews)
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
        
        let lhsChildren = lhs.subviews?["children"] as? [StaticElement]
        let rhsChildren = rhs.subviews?["children"] as? [StaticElement]
        if let lhsChildren, let rhsChildren {
            guard lhsChildren.count == rhsChildren.count else { return false }
            return zip(lhsChildren, rhsChildren).allSatisfy { $0 == $1 }
        }
        return (lhsChildren == nil) && (rhsChildren == nil)
    }
}
