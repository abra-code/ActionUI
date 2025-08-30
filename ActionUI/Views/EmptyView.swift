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
    
    static var validateProperties: ([String : Any], any ActionUILogger) -> [String : Any] = { properties, _ in
        return properties
    }
        
    static var buildView: (any ActionUIElement, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        return SwiftUI.EmptyView()
    }
}
