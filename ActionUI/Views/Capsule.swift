// Sources/Views/Capsule.swift
/*
 Sample JSON for Capsule:
 {
   "type": "Capsule",
   "id": 1,
   "properties": {
     "style": "circular",    // Optional: "circular" (default) or "continuous" (squircle-style end caps)
     "fill": "blue",         // Optional: fill color/style string (e.g. "red", "primary", "tint")
     "stroke": "red",        // Optional: stroke color/style string (mutually exclusive with fill; fill takes priority)
     "strokeLineWidth": 2.0  // Optional: stroke line width (default 1.0, used with stroke)
   }
   // Note: Baseline View properties (frame, padding, foregroundStyle, background, opacity, cornerRadius, etc.)
   // are inherited via ActionUIRegistry.shared.applyViewModifiers.
 }
*/

import SwiftUI

struct Capsule: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        if let style = validated["style"] as? String {
            if style != "circular" && style != "continuous" {
                logger.log("Capsule style must be 'circular' or 'continuous'; ignoring", .warning)
                validated["style"] = nil
            }
        } else if validated["style"] != nil {
            logger.log("Capsule style must be a String; ignoring", .warning)
            validated["style"] = nil
        }
        if let fill = validated["fill"], !(fill is String) {
            logger.log("Capsule fill must be a String; ignoring", .warning)
            validated["fill"] = nil
        }
        if let stroke = validated["stroke"], !(stroke is String) {
            logger.log("Capsule stroke must be a String; ignoring", .warning)
            validated["stroke"] = nil
        }
        if validated["strokeLineWidth"] != nil {
            if validated.cgFloat(forKey: "strokeLineWidth") == nil {
                logger.log("Capsule strokeLineWidth must be a CGFloat; ignoring", .warning)
                validated["strokeLineWidth"] = nil
            }
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let style: RoundedCornerStyle = (properties["style"] as? String) == "continuous" ? .continuous : .circular
        let shape = SwiftUI.Capsule(style: style)

        if let fillStr = properties["fill"] as? String, let fillStyle = ColorHelper.resolveShapeStyle(fillStr) {
            return shape.fill(fillStyle)
        }
        if let strokeStr = properties["stroke"] as? String, let strokeStyle = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = properties.cgFloat(forKey: "strokeLineWidth") ?? 1.0
            return shape.stroke(strokeStyle, lineWidth: lineWidth)
        }
        return shape
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
