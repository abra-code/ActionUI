/*
 Sample JSON for EmptyView:
 {
   "type": "EmptyView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {}
   // Note: EmptyView has no specific properties. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers to the group as a whole.
 }
*/

import SwiftUI

struct EmptyView: ActionUIViewConstruction {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        return properties // No specific properties to validate; rely on external View.validateProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        return AnyView(SwiftUI.EmptyView())
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        return view // No specific modifiers beyond base View properties
    }
}
