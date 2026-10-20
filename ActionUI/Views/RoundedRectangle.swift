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

extension RoundedRectangle {
    /// RoundedRectangle's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum CornerStyle: String, Sendable, CaseIterable {
            case circular, continuous
        }

        var cornerRadius = 0.0
        var cornerStyle = CornerStyle.circular
        /// Colors and gradients stay as the names the renderer resolves.
        var fill: String?
        var stroke: String?
        var strokeLineWidth = 1.0

        init(_ properties: [String: Any]) {
            cornerRadius = properties.double(forKey: "cornerRadius") ?? 0.0
            cornerStyle = (properties["cornerStyle"] as? String).flatMap(CornerStyle.init(rawValue:)) ?? .circular
            fill = properties["fill"] as? String
            stroke = properties["stroke"] as? String
            strokeLineWidth = properties.double(forKey: "strokeLineWidth") ?? 1.0
        }
    }
}

struct RoundedRectangle: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        let cornerRadius = CGFloat(props.cornerRadius)
        let style: RoundedCornerStyle = {
            switch props.cornerStyle {
            case .circular: return .circular
            case .continuous: return .continuous
            }
        }()
        let shape = SwiftUI.RoundedRectangle(cornerRadius: cornerRadius, style: style)

        if let fillStr = props.fill, let fillStyle = ColorHelper.resolveShapeStyle(fillStr) {
            return shape.fill(fillStyle)
        }
        if let strokeStr = props.stroke, let strokeStyle = ColorHelper.resolveShapeStyle(strokeStr) {
            let lineWidth = CGFloat(props.strokeLineWidth)
            return shape.stroke(strokeStyle, lineWidth: lineWidth)
        }
        return shape
    }

    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in
        return view
    }
}
