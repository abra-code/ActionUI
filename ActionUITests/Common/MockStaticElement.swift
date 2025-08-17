@testable import ActionUI

// Mock StaticElement for testing, conforming to ActionUIElement
struct MockStaticElement: ActionUIElement {
    let id: Int
    let type: String
    let properties: [String: Any]
    let children: [any ActionUIElement]?
    
    init(id: Int = 1, type: String, properties: [String: Any] = [:], children: [any ActionUIElement]? = nil) {
        self.id = id
        self.type = type
        self.properties = properties
        self.children = children
    }
    
    // Codable conformance
    enum CodingKeys: String, CodingKey {
        case id, type, properties, children
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        // Decode properties as [String: Any] (simplified, assuming basic types for testing)
        let rawProperties = try container.decodeIfPresent([String: String].self, forKey: .properties) ?? [:]
        properties = rawProperties
        // Decode children as [MockStaticElement]?
        children = try container.decodeIfPresent([MockStaticElement].self, forKey: .children)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        // Encode properties as [String: String] (simplified for testing)
        try container.encode(properties as? [String: String], forKey: .properties)
        // Encode children as [MockStaticElement]?
        try container.encodeIfPresent(children as? [MockStaticElement], forKey: .children)
    }
}

