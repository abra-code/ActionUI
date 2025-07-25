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
    static var valueType: Any.Type? { Void.self }
    
    static var validateProperties: (([String: Any]) -> [String: Any])? = { properties in
        var validatedProperties = properties
        
        if let item = validatedProperties["item"] as? String, let _ = URL(string: item) {
            validatedProperties["item"] = item
        } else {
            print("Warning: ShareLink requires a valid 'item' URL; defaulting to nil")
            validatedProperties["item"] = nil
        }
        if validatedProperties["subject"] == nil {
            validatedProperties["subject"] = nil
        }
        if validatedProperties["message"] == nil {
            validatedProperties["message"] = nil
        }
        
        return validatedProperties
    }
    
    static var buildElement: ((ActionUIElement, Binding<[Int: Any]>, String, [String: Any]) -> AnyView)? = { element, state, windowUUID, validatedProperties in
        if #available(iOS 16.1, macOS 13.1, *) {
            guard let item = validatedProperties["item"] as? String, let url = URL(string: item) else {
                print("Warning: ShareLink requires a valid URL")
                return AnyView(SwiftUI.EmptyView())
            }
            let subject = validatedProperties["subject"] as? String
            let message = validatedProperties["message"] as? String
            return AnyView(
                SwiftUI.ShareLink(item: url, subject: Text(subject ?? ""), message: Text(message ?? ""))
            )
        } else {
            print("Warning: ShareLink requires iOS 16.1 or macOS 13.1")
            return AnyView(SwiftUI.EmptyView())
        }
    }
    
    static var applyModifiers: ((AnyView, [String: Any]) -> AnyView)? = { view, properties in
        var modifiedView = view
        if #available(iOS 16.1, macOS 13.1, *) {
            if let subject = properties["subject"] as? String {
                modifiedView = AnyView(modifiedView.overlay(Text(subject), alignment: .top))
            }
            if let message = properties["message"] as? String {
                modifiedView = AnyView(modifiedView.overlay(Text(message), alignment: .bottom))
            }
        }
        return modifiedView
    }
}
