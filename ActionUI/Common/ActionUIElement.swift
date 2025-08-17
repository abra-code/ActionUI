/*
 Sample JSON for ActionUIElement (base structure for all elements):
 {
   "type": "View",       // Matches the view class name (e.g., "DisclosureGroup", "Divider")
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},     // Optional: Dictionary of view-specific properties
   "children": []        // Optional: Array of child elements
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
    private static func generateNegativeID() -> Int {
        defer { negativeIDCounter -= 1 }
        return negativeIDCounter
    }
    
    // Initializes a StaticElement with optional ID, type, properties, and children
    init(id: Int = 0, type: String, properties: [String: Any], children: [any ActionUIElement]?) {
        self.id = id == 0 ? StaticElement.generateNegativeID() : id
        self.type = type
        self.properties = properties
        self.children = type == "EmptyView" ? nil : children
    }
    
    // Coding keys for JSON serialization
    enum CodingKeys: String, CodingKey {
        case id, type, properties, children
    }
    
    // Decodes a StaticElement from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? StaticElement.generateNegativeID()
        type = try container.decode(String.self, forKey: .type)
        let rawProperties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties) ?? [:]
        properties = try rawProperties.mapValues { try AnyCodable.convertAnyCodableToAny($0) }
        if let childrenArray = try container.decodeIfPresent([AnyCodable].self, forKey: .children) {
            children = try childrenArray.map { try $0.asActionUIElement() }
        } else {
            children = nil
        }
    }
    
    // Encodes a StaticElement to JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        // Encode properties using AnyCodable to handle serialization
        let encodableProperties = try properties.mapValues { try AnyCodable.convertAnyToAnyCodable($0) }
        try container.encodeIfPresent(encodableProperties, forKey: .properties)
        // Encode children using AnyCodable to handle ActionUIElement array
        if let children = children {
            let encodableChildren = children.map { AnyCodable($0) }
            try container.encodeIfPresent(encodableChildren, forKey: .children)
        } else {
            try container.encodeNil(forKey: .children)
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
        self.init(id: id, type: type, properties: properties, children: children)
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
