/*
 Sample JSON for ShareLink:
 {
   "type": "ShareLink",
   "id": 1,
   "properties": {
     "item": "https://example.com",
     "subject": "Check this out",
     "message": "Look at this link!"
   }
   // Note: These properties are specific to ShareLink. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ShareLink: ActionUIViewConstruction {
    // Design decision: Defines valueType as Void since ShareLink triggers actions without storing state
    
    static var validateProperties: ([String: Any]) -> [String: Any] = { properties in
        var validatedProperties = properties
        
        if let item = validatedProperties["item"] as? String, let _ = URL(string: item) {
            validatedProperties["item"] = item
        } else {
            print("Warning: ShareLink requires a valid 'item' URL; defaulting to nil")
            validatedProperties["item"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildView: (any ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> any SwiftUI.View = { element, state, windowUUID, properties in
        if #available(iOS 16.1, macOS 13.1, *) {
            guard let item = properties["item"] as? String, let url = URL(string: item) else {
                print("Warning: ShareLink requires a valid URL")
                return SwiftUI.EmptyView()
            }
            let subject = properties["subject"] as? String
            let message = properties["message"] as? String
            return SwiftUI.ShareLink(item: url, subject: SwiftUI.Text(subject ?? ""), message: SwiftUI.Text(message ?? ""))
        } else {
            print("Warning: ShareLink requires iOS 16.1 or macOS 13.1")
            return SwiftUI.EmptyView()
        }
    }    
}
