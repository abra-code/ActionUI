// Sources/Views/Color.swift
/*
 Sample JSON for Color:
 {
   "type": "Color",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "color": "blue"   // Required: a color string - a named color ("red", "primary"/"secondary"),
                        // a hex string ("#RRGGBB" / "#RRGGBBAA"), or "<color>.opacity(<fraction>)".
   }
   // SwiftUI's `Color` is itself a View: a greedy block that fills the proposed space - the
   // canonical way to use a solid color as a view (a colored divider, a tinted background block),
   // simpler than a Rectangle().fill(). Give it a `frame` to size it (e.g. height 2 for a divider).
   // Baseline View properties (frame, padding, opacity, cornerRadius, etc.) are inherited via
   // ActionUIRegistry.shared.applyViewModifiers.
 }
 // Observable state:
 //   value (SwiftUI.Color)  A runtime color override - nil means "use the `color` property". Settable via
 //                          setElementValue (a Color) or setElementValueFromString (a color string - "red",
 //                          "#FF0000", "blue.opacity(0.3)"). ActionUIView re-builds on the change, so it re-renders.
 NOTE: this `Color` is ActionUI's element type (registered as "Color"). It is a module-level type,
 so it shadows `SwiftUI.Color` for unqualified uses within ActionUI - the few SwiftUI color sites
 (ColorHelper, ColorPicker, ActionUIModel) are written as `SwiftUI.Color` to disambiguate.
*/

import SwiftUI

struct Color: ActionUIViewConstruction {
    // Optional SwiftUI.Color value: nil = use the `color` property, a Color = a runtime override (set via
    // setElementValue / setElementValueFromString). Mirrors Image's static-property-with-runtime-override shape.
    static var valueType: Any.Type = SwiftUI.Color?.self
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties
        if let color = validated["color"], !(color is String) {
            logger.log("Color color must be a String; ignoring", .warning)
            validated["color"] = nil
        }
        return validated
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        // Non-nil only when a color was set at runtime; nil means "use the `color` property" (buildView resolves it).
        return model.value as? SwiftUI.Color
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, model, _, properties, logger in
        // Runtime override takes precedence (ActionUIView re-builds this when model.value changes).
        if let color = model.value as? SwiftUI.Color {
            return color
        }
        let colorStr = properties["color"] as? String
        if let colorStr, !colorStr.isEmpty {
            if let resolved = ColorHelper.resolveColor(colorStr) {
                return resolved
            }
            logger.log("Unknown color \"\(colorStr)\" for Color view; rendering clear", .warning)
        } else {
            logger.log("Color view requires a 'color' string; rendering clear", .warning)
        }
        return SwiftUI.Color.clear
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
