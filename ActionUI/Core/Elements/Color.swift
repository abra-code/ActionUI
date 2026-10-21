// Core/Elements/Color.swift
/*
 Sample JSON for Color:
 {
   "type": "Color",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "color": "blue"   // Required: a color string - a named color ("red", "primary"/"secondary"),
                        // a hex string ("#RRGGBB" / "#RRGGBBAA"), or "<color>.opacity(<fraction>)".
   }
   // A solid color as a view: a greedy block that fills the proposed space - the canonical way
   // to use a solid color as a view (a colored divider, a tinted background block), simpler than
   // a Rectangle().fill(). Give it a `frame` to size it (e.g. height 2 for a divider). Baseline View
   // properties (frame, padding, opacity, cornerRadius, etc.) are inherited.
 }
 // Observable state:
 //   value (ColorSpec?)  A runtime color override - nil means "use the `color` property". Settable via
 //                       setElementValue (a ColorSpec; on Apple a SwiftUI Color too) or
 //                       setElementValueFromString (a color string - "red", "#FF0000", "blue.opacity(0.3)").
 NOTE: this `Color` is ActionUI's element type (registered as "Color"). It is a module-level type,
 so it shadows `SwiftUI.Color` for unqualified uses within ActionUI - the SwiftUI color sites are
 written as `SwiftUI.Color` to disambiguate.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Color {
    /// Color's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// The color name the renderer resolves.
        var color: String?

        init(_ properties: [String: Any]) {
            color = properties["color"] as? String
        }
    }
}

struct Color: ActionUIElementSpec {
    // Optional ColorSpec value: nil = use the `color` property, a ColorSpec = a runtime override (set via
    // setElementValue / setElementValueFromString). Mirrors Image's static-property-with-runtime-override shape.
    static var valueType: Any.Type = ColorSpec?.self
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var initialValue: (ViewModel) -> Any? = { model in
        // Non-nil only when a color was set at runtime; nil means "use the `color` property" (the renderer resolves it).
        return model.value as? ColorSpec
    }
}
