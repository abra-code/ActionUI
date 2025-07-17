import SwiftUI

protocol UIElement {
    var id: Int { get }
    var type: String { get }
    var properties: [String: Any] { get }
    var children: [UIElement]? { get }
}

protocol StaticElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any]
}

struct StaticElement: UIElement, Codable {
    let id: Int
    let type: String
    let properties: [String: Any]
    let children: [UIElement]?
    
    private static var negativeIDCounter: Int = -1
    
    private static func generateNegativeID() -> Int {
        defer { negativeIDCounter -= 1 }
        return negativeIDCounter
    }
    
    private static let knownTypes: Set<String> = [
		"AsyncImage",
		"Button",
//		"ComboBox", DISABLED multi-part
		"EmptyView",
		"Grid",
		"Group",
		"HStack",
		"Image",
		"LazyHGrid",
		"LazyHStack",
		"LazyVGrid",
		"LazyVStack",
		"List",
		"Picker",
		"Spacer",
		"Table",
		"Text",
		"TextEditor",
		"TextField",
		"Toggle",
		"View",
		"VStack",
		"ZStack"
    ]
    
    private static let validators: [String: (StaticElement.Type) -> ([String: Any]) -> [String: Any]] = [
        "AsyncImage": { _ in AsyncImage.validateProperties },
        "Button": { _ in Button.validateProperties },
//        "ComboBox": { _ in ComboBox.validateProperties }, DISABLED
        "EmptyView": { _ in EmptyView.validateProperties },
        "Grid": { _ in Grid.validateProperties },
        "Group": { _ in Group.validateProperties },
        "HStack": { _ in HStack.validateProperties },
        "Image": { _ in Image.validateProperties },
        "LazyHGrid": { _ in LazyHGrid.validateProperties },
        "LazyHStack": { _ in LazyHStack.validateProperties },
        "LazyVGrid": { _ in LazyVGrid.validateProperties },
        "LazyVStack": { _ in LazyVStack.validateProperties },
        "List": { _ in List.validateProperties },
        "Picker": { _ in Picker.validateProperties },
        "Spacer": { _ in Spacer.validateProperties },
        "Table": { _ in Table.validateProperties },
        "Text": { _ in Text.validateProperties },
        "TextEditor": { _ in TextEditor.validateProperties },
        "TextField": { _ in TextField.validateProperties },
        "Toggle": { _ in Toggle.validateProperties },
        "View": { _ in View.validateProperties },
        "VStack": { _ in VStack.validateProperties },
        "ZStack": { _ in ZStack.validateProperties }
    ]
    
    init(id: Int = 0, type: String, properties: [String: Any], children: [UIElement]?) {
        let validatedType = StaticElement.knownTypes.contains(type) ? type : {
            print("Warning: Unknown type '\(type)' \(type == "Table" ? "(Table is macOS-only)" : type == "ComboBox" ? "(ComboBox is macOS/iOS/iPadOS-only)" : ""); defaulting to EmptyView")
            return "EmptyView"
        }()
        
        let validatedProperties = validatedType == "EmptyView" ? [:] : (StaticElement.validators[validatedType]?(StaticElement.self)?(properties) ?? properties)
        
        self.id = id == 0 ? StaticElement.generateNegativeID() : id
        self.type = validatedType
        self.properties = validatedProperties
        self.children = validatedType == "EmptyView" ? nil : children
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, properties, children
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id) ?? StaticElement.generateNegativeID()
        type = try container.decode(String.self, forKey: .type)
        let rawProperties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties) ?? [:]
        properties = StaticElement.validators[type]?(StaticElement.self)?(rawProperties.mapValues { $0.value }) ?? rawProperties.mapValues { $0.value }
        if let childrenArray = try container.decodeIfPresent([AnyCodable].self, forKey: .children) {
            children = try childrenArray.map { try $0.decodeAsUIElement() }
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
    
    static func getValidatedProperties(element: UIElement, state: Binding<[Int: Any]>) -> [String: Any] {
        if state.wrappedValue[element.id] == nil {
            state.wrappedValue[element.id] = [
                "value": "",
                "validatedProperties": validateProperties(element.properties),
                "rawProperties": element.properties
            ]
        }
        
        let currentState = state.wrappedValue[element.id] as? [String: Any] ?? [:]
        let rawProperties = currentState["rawProperties"] as? [String: Any] ?? [:]
        let validatedProperties: [String: Any]
        
        if rawProperties != element.properties {
            validatedProperties = validateProperties(element.properties)
            var newState = currentState
            newState["validatedProperties"] = validatedProperties
            newState["rawProperties"] = element.properties
            state.wrappedValue[element.id] = newState
        } else {
            validatedProperties = currentState["validatedProperties"] as? [String: Any] ?? validateProperties(element.properties)
        }
        
        return validatedProperties
    }
}
