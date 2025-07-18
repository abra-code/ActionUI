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
   // Note: These properties are specific to ScrollViewReader. Baseline View properties (padding, hidden, foregroundColor, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ModifierRegistry.shared.applyModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

struct ScrollViewReader: StaticElement, ViewBuilder {
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
    
    static func register(in registry: ViewBuilderRegistry) {
        registry.register("ScrollViewReader") { element, state, windowUUID in
            let properties = StaticElement.getValidatedProperties(element: element, state: state)
            let content = properties["content"] as? [String: Any] ?? ["type": "EmptyView", "properties": [:]]
            let scrollTo = properties["scrollTo"] as? Int
            let anchor = (properties["anchor"] as? String).flatMap {
                switch $0 {
                case "top": return UnitPoint.top
                case "bottom": return UnitPoint.bottom
                default: return UnitPoint.center
                }
            } ?? .center
            return AnyView(
                ScrollViewReader { proxy in
                    ViewBuilderRegistry.shared.buildView(from: content, state: state, windowUUID: windowUUID)
                        .onAppear {
                            if let scrollTo = scrollTo {
                                withAnimation {
                                    proxy.scrollTo(scrollTo, anchor: anchor)
                                }
                            }
                        }
                }
            )
        }
    }
    
    static func registerModifiers(registry: ModifierRegistry) {
        registry.register("scrollTo") { view, properties in
            guard let scrollTo = properties["scrollTo"] as? Int else { return view }
            if let reader = view as? ScrollViewReaderRepresentable {
                withAnimation {
                    reader.proxy.scrollTo(scrollTo, anchor: .center)
                }
            }
            return view
        }
        registry.register("anchor") { view, properties in
            guard let anchor = properties["anchor"] as? String else { return view }
            let unitPoint = {
                switch anchor {
                case "top": return UnitPoint.top
                case "bottom": return UnitPoint.bottom
                default: return UnitPoint.center
                }
            }()
            if let reader = view as? ScrollViewReaderRepresentable {
                // Anchor adjustment would typically occur with scrollTo; this is a placeholder
            }
            return view
        }
    }
}

// Placeholder protocol for ScrollViewReaderRepresentable (to be refined with actual proxy access)
protocol ScrollViewReaderRepresentable: View {
    var proxy: ScrollViewProxy { get }
}
