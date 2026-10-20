// Core/Elements/VStack.swift
/*
 Sample JSON for VStack:
 {
   "type": "VStack",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "spacing": 10.0,     // Optional: CGFloat for spacing between elements
     "alignment": "center" // Optional: Horizontal alignment (e.g., "leading", "center", "trailing")
   },
   "children": [         // Static children — mutually exclusive with "template"
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ],
   // OR data-driven mode
   "template": {      // Presence of "template" activates data-driven rendering; "id" required for setElementRows
      "type": "Label",
      "properties": { "title": "$2", "systemImage": "$1" }
   }
   //
   // Column reference syntax in template string properties:
   //   $1  — column 0 (first column, 1-based)
   //   $2  — column 1 (second column, 1-based)
   //   $N  — column N-1
   //   $0  — all columns joined with ", "
   //
   // Data is set at runtime via setElementRows(windowUUID:viewID:rows:).
   // states["content"] ([[String]]) holds the current rows.
   //
   // Note: These properties are specific to VStack. Baseline View properties (padding, hidden,
   // foregroundStyle, font, background, frame, opacity, cornerRadius, disabled) and
   // additional View protocol modifiers are inherited and applied via
   // ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
   //
   // "actionID" is the exception. A VStack carrying one becomes tappable as a WHOLE - the
   // rich-cell idiom: one tap target for an avatar + name + status line, instead of a small
   // Button wedged inside the cell. It is wired by ContainerAction.apply
   // (Helpers/ContainerActionHelper.swift), called from ActionUIRegistry.applyViewModifiers
   // AFTER the baseline modifiers, so the target covers the container's FINAL box - frame,
   // padding and background included. Inside a template row it dispatches with the owning
   // container's id as viewID and the row index as viewPartID, exactly as a Button in that
   // row does; outside one, with its own id and viewPartID 0. The innermost action wins: a
   // nested Button, a nested tappable container, or an enclosing List row's selection never
   // fire alongside it. The cell is also announced as a single button to VoiceOver. A blank
   // actionID is ignored, and a disabled container (or one inside a disabled ancestor) is
   // inert.
 }
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension VStack {
    /// VStack's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Alignment: String, Sendable, CaseIterable {
            case leading, center, trailing
        }

        var spacing = 0.0
        var alignment = Alignment.center

        init(_ properties: [String: Any]) {
            spacing = properties.double(forKey: "spacing") ?? 0.0
            alignment = (properties["alignment"] as? String).flatMap(Alignment.init(rawValue:)) ?? .center
        }
    }
}

struct VStack: ActionUIElementSpec {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = ["children": .flat]
}
