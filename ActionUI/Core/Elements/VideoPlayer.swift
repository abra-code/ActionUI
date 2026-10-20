// Core/Elements/VideoPlayer.swift
/*
 Sample JSON for VideoPlayer:
 {
   "type": "VideoPlayer",
   "id": 1,
   "properties": {
     "url": "https://example.com/video.mp4", // Required: URL string, displays Label with error message if invalid or missing
     "autoplay": true    // Optional: Boolean for autoplay, ignored if nil
   }
   // Note: These properties are specific to VideoPlayer. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension VideoPlayer {
    /// VideoPlayer's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var url: String?
        var autoplay: Bool?

        init(_ properties: [String: Any]) {
            url = properties["url"] as? String
            autoplay = properties["autoplay"] as? Bool
        }
    }
}

struct VideoPlayer: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = String.self // Non-optional String for URL

    static var initialValue: (ViewModel) -> Any? = { model in
        if let initialValue = model.value as? String {
            return initialValue
        }
        let initialValue = Props(model.properties).url ?? ""
        return initialValue
    }
}
