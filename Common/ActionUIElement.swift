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

protocol ActionUIElement {
    var id: Int { get }
    var type: String { get }
    var properties: [String: Any] { get }
    var children: [ActionUIElement]? { get }
}

protocol ActionUIViewConstruction {
    // Design decision: Optional valueType allows views to omit state; defaults to Void in ActionUIRegistry
    static var valueType: Any.Type? { get }
    
    // Design decision: Optional closure allows views to skip validation; defaults to returning input properties if nil
    static var validateProperties: (([String: Any]) -> [String: Any])? { get }
    
    // Design decision: Optional closure allows views to defer to defaults; returns EmptyView if nil
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? { get }
    
    // Design decision: Optional closure allows views to skip custom modifiers; defaults to returning input view if nil
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? { get }
}

struct StaticElement: ActionUIElement, Codable {
    let id: Int
    let type: String
    let properties: [String: Any]
    let children: [ActionUIElement]?
    
    private static var negativeIDCounter: Int = -1
    
    private static func generateNegativeID() -> Int {
        defer { negativeIDCounter -= 1 }
        return negativeIDCounter
    }
    
    init(id: Int = 0, type: String, properties: [String: Any], children: [ActionUIElement]?) {
        self.id = id == 0 ? StaticElement.generateNegativeID() : id
        self.type = type
        self.properties = properties
        self.children = type == "EmptyView" ? nil : children
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, properties, children
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? StaticElement.generateNegativeID()
        type = try container.decode(String.self, forKey: .type)
        let rawProperties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties) ?? [:]
        properties = rawProperties.mapValues { $0.value }
        if let childrenArray = try container.decodeIfPresent([AnyCodable].self, forKey: .children) {
            children = try childrenArray.map { try $0.decodeAsActionUIElement() }
        } else {
            children = nil
        }
    }
    
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
    
    static func register<T: ActionUIViewConstruction>(registry: ActionUIRegistry) {
        // Design decision: Registers the type itself, allowing runtime lookup of optional closure properties
        registry.registerView(type: String(describing: T.self), constructionType: T.self)
    }
}
