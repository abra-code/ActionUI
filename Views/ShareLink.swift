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
 }
*/

import SwiftUI

struct ShareLink: StaticElement, ViewBuilder {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
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
    
    static func register(in registry: ViewBuilderRegistry) {
        if #available(iOS 16.1, macOS 13.1, *) {
            registry.register("ShareLink") { element, state, windowUUID in
                let properties = StaticElement.getValidatedProperties(element: element, state: state)
                guard let item = properties["item"] as? String, let url = URL(string: item) else {
                    print("Warning: ShareLink requires a valid URL")
                    return AnyView(EmptyView())
                }
                let subject = properties["subject"] as? String
                let message = properties["message"] as? String
                return AnyView(
                    ShareLink(item: url, subject: Text(subject ?? ""), message: Text(message ?? ""))
                )
            }
        } else {
            registry.register("ShareLink") { _, _, _ in
                print("Warning: ShareLink requires iOS 16.1 or macOS 13.1")
                return AnyView(EmptyView())
            }
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        if #available(iOS 16.1, macOS 13.1, *) {
            registry.register("subject") { view, properties in
                guard let subject = properties["subject"] as? String else { return view }
                return AnyView((view as? some View)?.overlay(Text(subject), alignment: .top) ?? Text(subject))
            }
            registry.register("message") { view, properties in
                guard let message = properties["message"] as? String else { return view }
                return AnyView((view as? some View)?.overlay(Text(message), alignment: .bottom) ?? Text(message))
            }
        }
    }
}
