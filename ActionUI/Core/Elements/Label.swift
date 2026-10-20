// Core/Elements/Label.swift
/*
 Sample JSON for Label:
 {
   "type": "Label",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Title",    // Optional: String for title text, defaults to ""
     "systemImage": "star.fill", // Optional: String for SF Symbol, defaults to nil
     "imageName": "customIcon" // Optional: String for asset catalog image, defaults to nil
   }
   // Note: These properties are specific to Label. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Label {
    /// Label's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = ""
        var systemImage: String?
        var imageName: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            systemImage = properties["systemImage"] as? String
            imageName = properties["imageName"] as? String
        }
    }
}

struct Label: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // The mutable runtime value is the title string
    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        // If value was already set programmatically before view creation, preserve it
        if let storedValue = model.value as? String {
            return storedValue
        }
        
        // Otherwise use the title from the properties
        let propertiesValue = Props(model.properties).title
        return propertiesValue
    }
}
