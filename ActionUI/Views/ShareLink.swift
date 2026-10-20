// Sources/Views/ShareLink.swift
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

import SwiftUI

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

struct ShareLink: ActionUIViewConstruction {
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = Void.self
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        guard let item = props.item, let url = URL(string: item) else {
            logger.log("ShareLink missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let subject = props.subject
        let message = props.message
        return SwiftUI.ShareLink(item: url, subject: SwiftUI.Text(subject ?? ""), message: SwiftUI.Text(message ?? ""))
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
