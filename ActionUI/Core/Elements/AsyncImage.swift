// Core/Elements/AsyncImage.swift
/*
 Sample JSON for AsyncImage:
 {
   "type": "AsyncImage",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://example.com/image.jpg", // Required: String for web or local file URL, returns placeholder if nil or invalid
     "placeholder": "photo",                 // Optional: String for SF Symbol or asset name, defaults to "photo" in buildView
     "resizable": true,                     // Optional: Boolean to make image resizable, defaults to true in buildView
     "contentMode": "fit"                   // Optional: "fit" or "fill" for scaling mode, defaults to "fit" in buildView
   }
   // Note: These properties are specific to AsyncImage. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   // Note: Invalid URLs (e.g., "invalid-url") are allowed and will construct AsyncImage, which may fail to download but should not crash.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension AsyncImage {
    /// AsyncImage's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum ContentMode: String, Sendable, CaseIterable {
            case fit, fill
        }

        var url: String?
        var placeholder = "photo"
        var resizable = true
        /// Anything but "fill" (absent, unknown, not a String) is "fit".
        var contentMode = ContentMode.fit

        init(_ properties: [String: Any]) {
            url = properties["url"] as? String
            placeholder = properties["placeholder"] as? String ?? "photo"
            resizable = properties["resizable"] as? Bool ?? true
            contentMode = (properties["contentMode"] as? String).flatMap(ContentMode.init(rawValue:)) ?? .fit
        }
    }
}

struct AsyncImage: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    // The runtime value of an AsyncImage is its URL string.
    // Setting the value programmatically overrides the static "url" property.
    static var valueType: Any.Type = String.self

    static var initialValue: (ViewModel) -> Any? = { model in
        // Runtime value (set via set_string / set_value) takes precedence
        if let storedValue = model.value as? String {
            return storedValue
        }
        // Fall back to the static "url" property from JSON
        return Props(model.properties).url
    }
}
