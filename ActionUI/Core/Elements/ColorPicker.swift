// Core/Elements/ColorPicker.swift
/*
 Sample JSON for ColorPicker:
 {
   "type": "ColorPicker",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "title": "Pick a Color", // Optional: String for title, defaults to empty
     "selectedColor": "#FF0000", // Optional: Initial color (hex or named color), defaults to clear
     "actionID": "colorpicker.action" // Optional: String for action identifier, triggers on color change
   }
   // Note: These properties are specific to ColorPicker. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited.
 }
 // Observable state:
 //   value (ColorSpec)  The selected color: the picked color as .rgba, or the `selectedColor`
 //                      property until one is picked.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ColorPicker {
    /// ColorPicker's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        var title = ""
        /// The initial color as written; the spec parses it.
        var selectedColor: String?
        var actionID: String?

        init(_ properties: [String: Any]) {
            title = properties["title"] as? String ?? ""
            selectedColor = properties["selectedColor"] as? String
            actionID = properties["actionID"] as? String
        }
    }
}

struct ColorPicker: ActionUIElementSpec {
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var valueType: Any.Type = ColorSpec.self // Value is the selected color

    // The selected color: the value once set or picked, else the `selectedColor` property, else clear.
    static var initialValue: (ViewModel) -> Any? = { model in
        if let selected = model.value as? ColorSpec {
            return selected
        }
        return ColorSpec.parse(Props(model.properties).selectedColor) ?? .named(.clear)
    }
}
