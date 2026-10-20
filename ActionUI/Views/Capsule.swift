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

extension Capsule {
    /// Capsule's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Style: String, Sendable, CaseIterable {
            case circular, continuous
        }

        var style = Style.circular
        /// Colors and gradients stay as the names the renderer resolves.
        var fill: String?
        var stroke: String?
        var strokeLineWidth = 1.0

        init(_ properties: [String: Any]) {
            style = (properties["style"] as? String).flatMap(Style.init(rawValue:)) ?? .circular
            fill = properties["fill"] as? String
            stroke = properties["stroke"] as? String
            strokeLineWidth = properties.double(forKey: "strokeLineWidth") ?? 1.0
        }
    }
}

struct Capsule: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, properties, _ in
        let props = Props(properties)
        let style: RoundedCornerStyle = {
            switch props.style {
            case .circular: return .circular
            case .continuous: return .continuous
            }
        }()
        let shape = SwiftUI.Capsule(style: style)

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
