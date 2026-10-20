// Core/Elements/ShareLink.swift
/*
 Sample JSON for ShareLink:
 {
   "type": "ShareLink",
   "id": 1,
   "properties": {
     "item": "https://example.com", // Optional: URL string, returns EmptyView if nil or invalid
     "subject": "Check this out", // Optional: String for subject, ignored if nil
     "message": "Look at this link!" // Optional: String for message, ignored if nil
   }
   // Note: These properties are specific to ShareLink. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ShareLink {
    /// ShareLink's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The URL string; nil when absent, not a String or not a valid URL.
        var item: String?
        var subject: String?
        var message: String?

        init(_ properties: [String: Any]) {
            item = (properties["item"] as? String).flatMap { URL(string: $0) == nil ? nil : $0 }
            subject = properties["subject"] as? String
            message = properties["message"] as? String
        }
    }
}

struct ShareLink: ActionUIElementSpec {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Void.self
}
