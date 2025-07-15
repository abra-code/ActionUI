
import SwiftUI

class UIModel: ObservableObject {
    static let shared = UIModel()
    
    @Published var descriptions: [String: UIElement] = [:]
    @Published var states: [String: [Int: Any]] = [:]
    
    func loadDescription(from data: Data, format: String, dialogGUID: String) throws {
        if format == "json" {
            let element = try JSONDecoder().decode(StaticElement.self, from: data)
            descriptions[dialogGUID] = element
        } else if format == "plist" {
            let element = try PropertyListDecoder().decode(StaticElement.self, from: data)
            descriptions[dialogGUID] = element
        } else {
            throw NSError(domain: "UIModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format: \(format)"])
        }
    }
    
    func cacheAsBinaryPlist(_ data: Data, format: String, to url: URL, dialogGUID: String) throws {
        try loadDescription(from: data, format: format, dialogGUID: dialogGUID)
        let plistData = try PropertyListEncoder().encode(descriptions[dialogGUID]!)
        try plistData.write(to: url)
    }
    
    func state(for dialogGUID: String) -> Binding<[Int: Any]> {
        Binding(
            get: { self.states[dialogGUID] ?? [:] },
            set: { self.states[dialogGUID] = $0 }
        )
    }
    
    func getControlValue(dialogGUID: String, controlID: Int, controlPartID: Int = 0) -> Any? {
        if let state = states[dialogGUID]?[controlID] as? [String: Any] {
            return state["value"]
        }
        return nil
    }
}
