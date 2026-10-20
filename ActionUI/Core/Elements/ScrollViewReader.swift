// Core/Elements/ScrollViewReader.swift
/*
 Sample JSON for ScrollViewReader:
 {
   "type": "ScrollViewReader",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view (typically ScrollView). Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "ScrollView", "properties": { "content": { "type": "Text", "properties": { "text": "Item 1" } } }
   },
   "properties": {
     "scrollTo": 5,       // Optional: Integer ID to scroll to, defaults to nil
     "anchor": "top"      // Optional: "top", "center", "bottom"; defaults to "center"
   }
   // Note: These properties are specific to ScrollViewReader. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ScrollViewReader {
    /// ScrollViewReader's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Anchor: String, Sendable, CaseIterable {
            case top, center, bottom
        }

        /// The id of the element to scroll to; an Int and nothing else.
        var scrollTo: Int?
        /// A name that is not one of the three, or no string, is center.
        var anchor = Anchor.center

        init(_ properties: [String: Any]) {
            scrollTo = properties["scrollTo"] as? Int
            anchor = (properties["anchor"] as? String).flatMap(Anchor.init(rawValue:)) ?? .center
        }
    }
}

struct ScrollViewReader: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
}
