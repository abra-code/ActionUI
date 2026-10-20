// Core/Elements/GeometryReader.swift
/*
 Sample JSON for GeometryReader:
 {
   "type": "GeometryReader",
   "id": 1,              // Required: Non-zero positive integer (size is reported via states on this model)
   "content": {          // Required: Single child view. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Content" }
   },
   "properties": {
     "alignment": "center"  // Optional: Content alignment — "topLeading" (SwiftUI default), "center", "top",
                             //   "bottom", "leading", "trailing", "topTrailing", "bottomLeading", "bottomTrailing".
                             //   GeometryReader's SwiftUI default is topLeading; set "center" to center content.
   }
 }

 // Behavior: GeometryReader is a greedy container — it expands to fill all available space
 // offered by its parent, regardless of its content's size. This makes it useful for:
 //   - Forcing a view to fill available space (e.g., full-screen overlays)
 //   - Reading the container's size for responsive layout decisions
 // SwiftUI default alignment is .topLeading (not .center like most containers).
 //
 // The container's size is exposed via observable state so clients can react to layout:
 //   states["size"]  [Double, Double]   Container width and height as [width, height].
 //                                      Updated when the container's size changes.
 //                                      Read via getElementState(windowUUID:, viewID:, key: "size").
 //
 // Platform behavior: Identical on iOS and macOS — always greedy, always topLeading default.
 // As a subview of HStack/VStack, GeometryReader consumes all remaining flexible space,
 // pushing siblings to their minimum size. Use with care in stacks.
 //
 // Note: These properties are specific to GeometryReader. Baseline View properties (padding, hidden,
 // foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional
 // View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to:
 // baseView, properties: element.properties).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension GeometryReader {
    /// GeometryReader's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
        }

        /// A name that is not one of the nine, or no string, is topLeading (GeometryReader's own default).
        var alignment = Alignment.topLeading

        init(_ properties: [String: Any]) {
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .topLeading
        }
    }
}

struct GeometryReader: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states["size"] == nil {
            states["size"] = [0.0, 0.0] as [Double]
        }
        return states
    }
}
