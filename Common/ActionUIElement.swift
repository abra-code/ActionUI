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

protocol ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any]
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView
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
    
    static func register<T: ActionUIViewElement>(registry: ActionUIRegistry) {
        let registration = ActionUIRegistry.ViewRegistration(
            buildElement: T.buildElement,
            validateProperties: T.validateProperties,
            applyModifiers: T.applyModifiers
        )
        registry.registerView(type: String(describing: T.self), registration: registration)
    }
}
