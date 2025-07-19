import SwiftUI

class ActionUIModel: ObservableObject {
    static let shared = ActionUIModel()
    
    @Published var descriptions: [String: ActionUIElement] = [:]
    @Published var states: [String: [Int: Any]] = [:]
    
    func loadDescription(from data: Data, format: String, windowUUID: String) throws {
        if format == "json" {
            let element = try JSONDecoder().decode(StaticElement.self, from: data)
            descriptions[windowUUID] = element
        } else if format == "plist" {
            let element = try PropertyListDecoder().decode(StaticElement.self, from: data)
            descriptions[windowUUID] = element
        } else {
            throw NSError(domain: "ActionUIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }
    
    func cacheAsBinaryPlist(_ data: Data, format: String, to url: URL, windowUUID: String) throws {
        try loadDescription(from: data, format: format, windowUUID: windowUUID)
        let plistData = try PropertyListEncoder().encode(descriptions[windowUUID]!)
        try plistData.write(to: url)
    }
    
    func state(for windowUUID: String) -> Binding<[Int: Any]> {
        Binding(
            get: { self.states[windowUUID] ?? [:] },
            set: { self.states[windowUUID] = $0 }
        )
    }
    
    func getControlValue(windowUUID: String, controlID: Int, controlPartID: Int = 0) -> Any? {
        if let state = states[windowUUID]?[controlID] as? [String: Any] {
            return state["value"]
        }
        return nil
    }
}
