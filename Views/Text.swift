
/*
 Sample JSON for Text:
 {
   "type": "Text",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "text": "Hello, World!", // Optional: String, defaults to empty string
     "padding": 10.0,        // Optional: CGFloat for padding
     "font": "body",         // Optional: SwiftUI font role (e.g., "largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "caption", "caption2", "footnote") or custom font name (e.g., "Helvetica", "Times New Roman"; resolved by FontUtility with Dynamic Type), defaults to "body"
     "foregroundColor": "blue", // Optional: SwiftUI color (e.g., "red", "blue", "green", "yellow", "purple", "pink", "mint", "teal", "cyan", "indigo", "brown", "gray", "black", "white", "primary", "secondary") or hex RGBA (e.g., "#FF0000" for red, "#FF0000FF" for red with full opacity), resolved by ColorUtility, defaults to primary
     "hidden": false         // Optional: Boolean to hide the view
   }
 }
*/

import SwiftUI

struct Text: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        let supportedProperties = ["text", "padding", "font", "foregroundColor", "hidden"]
        var validatedProperties = properties
        
        if validatedProperties["text"] == nil {
            validatedProperties["text"] = ""
        }
        
        return validatedProperties.filter { key, _ in
            if supportedProperties.contains(key) {
                return true
            } else {
                print("Warning: Property '\(key)' is not supported for Text; ignoring")
                return false
            }
        }
    }
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("Text") { element, state, dialogGUID in
            let properties = getValidatedProperties(element: element, state: state)
            
            let text = properties["text"] as? String ?? ""
            let padding = properties["padding"] as? CGFloat ?? 0.0
            let font = properties["font"]
            let foregroundColor = properties["foregroundColor"]
            let hidden = properties["hidden"] as? Bool ?? false
            
            return AnyView(
                SwiftUI.Text(text)
                    .font(FontUtility.resolveFont(font))
                    .foregroundColor(ColorUtility.resolveColor(foregroundColor))
                    .padding(padding)
                    .opacity(hidden ? 0 : 1)
            )
        }
    }
}
