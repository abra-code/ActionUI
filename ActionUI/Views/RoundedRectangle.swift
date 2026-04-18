// Sources/Views/RoundedRectangle.swift
/*
 Sample JSON for RoundedRectangle:
 {
   "type": "RoundedRectangle",
   "id": 1,
   "properties": {
     "cornerRadius": 12.0,   // Required: corner radius in points (default 0)
     "cornerStyle": "circular",  // Optional: "circular" (default) or "continuous" (squircle-style)
     "fill": "blue",         // Optional: fill color/style string (e.g. "red", "primary", "tint")
     "stroke": "red",        // Optional: stroke color/style string (mutually exclusive with fill; fill takes priority)
     "strokeLineWidth": 2.0  // Optional: stroke line width (default 1.0, used with stroke)
   }
   // Note: Baseline View properties (frame, padding, foregroundStyle, background, opacity, etc.)
   // are inherited via ActionUIRegistry.shared.applyViewModifiers.
 }
*/

import SwiftUI

struct RoundedRectangle: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        if let cornerRadius = validated["cornerRadius"] {
            if validated.cgFloat(forKey: "cornerRadius") == nil {
                logger.log("RoundedRectangle cornerRadius must be a CGFloat; defaulting to 0", .warning)
                validated["cornerRadius"] = nil
            }
        }
        if let style = validated["cornerStyle"] as? String {
            if style != "circular" && style != "continuous" {
                logger.log("RoundedRectangle cornerStyle must be 'circular' or 'continuous'; ignoring", .warning)
                validated["cornerStyle"] = nil
            }
        } else if validated["cornerStyle"] != nil {
            logger.log("RoundedRectangle cornerStyle must be a String; ignoring", .warning)
            validated["cornerStyle"] = nil
        }
        if let fill = validated["fill"], !(fill is String) {
            logger.log("RoundedRectangle fill must be a String; ignoring", .warning)
            validated["fill"] = nil
        }
        if let stroke = validated["stroke"], !(stroke is String) {
            logger.log("RoundedRectangle stroke must be a String; ignoring", .warning)
            validated["stroke"] = nil
        }
        if validated["strokeLineWidth"] != nil {
            if validated.cgFloat(forKey: "strokeLineWidth") == nil {
                logger.log("RoundedRectangle strokeLineWidth must be a CGFloat; ignoring", .warning)
                validated["strokeLineWidth"] = nil
            }
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let cornerRadius = properties.cgFloat(forKey: "cornerRadius") ?? 0
        let style: RoundedCornerStyle = (properties["cornerStyle"] as? String) == "continuous" ? .continuous : .circular
        let shape = SwiftUI.RoundedRectangle(cornerRadius: cornerRadius, style: style)

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
