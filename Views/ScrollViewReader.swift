/*
 Sample JSON for ScrollViewReader:
 {
   "type": "ScrollViewReader",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "content": { "type": "ScrollView", "properties": { "content": { "type": "Text", "properties": { "text": "Item 1" } } } }, // Required: Nested ScrollView
     "scrollTo": 5,       // Optional: Integer ID to scroll to, defaults to nil
     "anchor": "top"      // Optional: "top", "center", "bottom"; defaults to "center"
   }
   // Note: These properties are specific to ScrollViewReader. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ScrollViewReader: ActionUIViewElement {
    static func validateProperties(_ properties: [String: Any]) -> [String: Any] {
        var validatedProperties = View.validateProperties(properties)
        
        if validatedProperties["content"] == nil {
            print("Warning: ScrollViewReader requires 'content'; defaulting to EmptyView")
            validatedProperties["content"] = ["type": "EmptyView", "properties": [:]]
        }
        if let scrollTo = validatedProperties["scrollTo"] as? Int {
            validatedProperties["scrollTo"] = scrollTo
        }
        if let anchor = validatedProperties["anchor"] as? String,
           !["top", "center", "bottom"].contains(anchor) {
            print("Warning: ScrollViewReader anchor '\(anchor)' invalid; defaulting to 'center'")
            validatedProperties["anchor"] = "center"
        }
        
        return validatedProperties
    }
    
    static func buildElement(_ element: ActionUIElement, _ state: Binding<[Int: Any]>, _ windowUUID: String, validatedProperties: [String: Any]) -> AnyView {
        let content = validatedProperties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
        
        return AnyView(
            SwiftUI.ScrollViewReader { proxy in
                ActionUIView(element: try! StaticElement(from: content), state: state, windowUUID: windowUUID)
            }
        )
    }
    
    static func applyModifiers(_ view: AnyView, _ properties: [String: Any]) -> AnyView {
        var modifiedView = view
        if let scrollTo = properties["scrollTo"] as? Int {
            let anchor = (properties["anchor"] as? String).flatMap {
                switch $0 {
                case "top": return UnitPoint.top
                case "bottom": return UnitPoint.bottom
                default: return UnitPoint.center
                }
            } ?? .center
            modifiedView = AnyView(modifiedView.onAppear {
                if let reader = modifiedView as? ScrollViewReaderRepresentable {
                    withAnimation {
                        reader.proxy.scrollTo(scrollTo, anchor: anchor)
                    }
                }
            })
        }
        return modifiedView
    }
}

// Placeholder protocol for ScrollViewReaderRepresentable (to be refined with actual proxy access)
protocol ScrollViewReaderRepresentable: View {
    var proxy: ScrollViewProxy { get }
}
