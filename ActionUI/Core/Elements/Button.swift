// Core/Elements/Button.swift
/*
 Sample JSON for Button:
 {
   "type": "Button",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Click Me",    // Optional: String, defaults to empty in buildView
     "systemImage": "plus.circle", // Optional: SF Symbol name
     "assetImage": "Logo",   // Optional: name from Assets.xcassets
     "imageScale": "large",  // Optional: image scale: "small", "medium", "large". Defaults to "medium" if absent
     "role": "destructive"   // Optional: Button role (e.g., "destructive", "cancel")
   }
   // Note: These properties are specific to Button. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Button {
    /// Button's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Role: String, Sendable, CaseIterable {
            case destructive, cancel
        }

        enum ImageScale: String, Sendable, CaseIterable {
            case small, medium, large
        }

        var title = ""
        var systemImage: String?
        var assetImage: String?
        /// nil when absent or not a known name (the image keeps its medium scale).
        var imageScale: ImageScale?
        var role: Role?
        var actionID: String?
        var popoverActionID: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            systemImage = properties["systemImage"] as? String
            assetImage = properties["assetImage"] as? String
            // The name is matched in any letter case.
            imageScale = (properties["imageScale"] as? String).flatMap { ImageScale(rawValue: $0.lowercased()) }
            role = (properties["role"] as? String).flatMap(Role.init(rawValue:))
            actionID = properties["actionID"] as? String
            popoverActionID = properties["popoverActionID"] as? String
        }
    }
}

struct Button: ActionUIElementSpec {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // Button has no stateful value, only triggers actions
    static var valueType: Any.Type = Void.self
}
