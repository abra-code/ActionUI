/*
 Sample JSON for Group:
 {
   "type": "Group",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {},
   "children": [
     { "type": "Text", "properties": { "text": "Item 1" } },
     { "type": "Text", "properties": { "text": "Item 2" } }
   ]
   // Note: Group has no specific properties and does not control layout geometry, relying on the parent container for alignment and spacing. All properties/modifiers from the base View (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are supported and applied via ActionUIRegistry.shared.applyModifiers to the group as a whole.
 }
*/

import SwiftUI

struct Group: ActionUIViewConstruction {
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        let children = element.children ?? []
        
        return AnyView(
            SwiftUI.Group {
                ForEach(children.indices, id: \.self) { index in
                    ActionUIView(element: children[index], state: state, windowUUID: windowUUID)
                }
            }
        )
    }    
}
