// Sources/Views/Rectangle.swift
/*
 Sample JSON for Rectangle:
 {
   "type": "Rectangle",
   "id": 1,
   "properties": {
     "fill": "blue",         // Optional: fill color/style string (e.g. "red", "primary", "tint")
     "stroke": "red",        // Optional: stroke color/style string (mutually exclusive with fill; fill takes priority)
     "strokeLineWidth": 2.0  // Optional: stroke line width (default 1.0, used with stroke)
   }
   // Note: Baseline View properties (frame, padding, foregroundStyle, background, opacity, cornerRadius, etc.)
   // are inherited via ActionUIRegistry.shared.applyViewModifiers.
 }
*/

import SwiftUI

struct Rectangle: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        if let fill = validated["fill"], !(fill is String) {
            logger.log("Rectangle fill must be a String; ignoring", .warning)
            validated["fill"] = nil
        }
        if let stroke = validated["stroke"], !(stroke is String) {
            logger.log("Rectangle stroke must be a String; ignoring", .warning)
            validated["stroke"] = nil
        }
        if validated["strokeLineWidth"] != nil {
            if validated.cgFloat(forKey: "strokeLineWidth") == nil {
                logger.log("Rectangle strokeLineWidth must be a CGFloat; ignoring", .warning)
                validated["strokeLineWidth"] = nil
            }
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        if let fillStr = properties["fill"] as? String, let style = ColorHelper.resolveShapeStyle(fillStr) {
            return SwiftUI.Rectangle().fill(style)
        }
        if let strokeStr = properties["stroke"] as? String, let style = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = properties.cgFloat(forKey: "strokeLineWidth") ?? 1.0
            return SwiftUI.Rectangle().stroke(style, lineWidth: lineWidth)
        }
        return SwiftUI.Rectangle()
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
