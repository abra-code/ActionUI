// Core/Elements/Circle.swift
/*
 Sample JSON for Circle:
 {
   "type": "Circle",
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Circle {
    /// Circle's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        /// Colors and gradients stay as the names the renderer resolves.
        var fill: String?
        var stroke: String?
        var strokeLineWidth = 1.0

        init(_ properties: [String: Any]) {
            fill = properties["fill"] as? String
            stroke = properties["stroke"] as? String
            strokeLineWidth = properties.double(forKey: "strokeLineWidth") ?? 1.0
        }
    }
}

struct Circle: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil
}
