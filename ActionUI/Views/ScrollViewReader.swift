// Sources/Views/ScrollViewReader.swift
/*
 Sample JSON for ScrollViewReader:
 {
   "type": "ScrollViewReader",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view (typically ScrollView). Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "ScrollView", "properties": { "content": { "type": "Text", "properties": { "text": "Item 1" } } }
   },
   "properties": {
     "scrollTo": 5,       // Optional: Integer ID to scroll to, defaults to nil
     "anchor": "top"      // Optional: "top", "center", "bottom"; defaults to "center"
   }
   // Note: These properties are specific to ScrollViewReader. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

extension ScrollViewReader {
    /// ScrollViewReader's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Anchor: String, Sendable, CaseIterable {
            case top, center, bottom
        }

        /// The id of the element to scroll to; an Int and nothing else.
        var scrollTo: Int?
        /// A name that is not one of the three, or no string, is center.
        var anchor = Anchor.center

        init(_ properties: [String: Any]) {
            scrollTo = properties["scrollTo"] as? Int
            anchor = (properties["anchor"] as? String).flatMap(Anchor.init(rawValue:)) ?? .center
        }
    }
}

struct ScrollViewReader: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        
        return SwiftUI.ScrollViewReader { proxy in
            if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        var modifiedView = view
        let props = Props(properties)
        if let scrollTo = props.scrollTo {
            let anchor: UnitPoint = {
                switch props.anchor {
                case .top: return UnitPoint.top
                case .bottom: return UnitPoint.bottom
                case .center: return UnitPoint.center
                }
            }()
            modifiedView = modifiedView.onAppear {
                if let reader = modifiedView as? any ScrollViewReaderRepresentable {
                    withAnimation {
                        reader.proxy.scrollTo(scrollTo, anchor: anchor)
                    }
                }
            }
        }
        return modifiedView
    }
}

// Placeholder protocol for ScrollViewReaderRepresentable (to be refined with actual proxy access)
protocol ScrollViewReaderRepresentable: SwiftUI.View {
    var proxy: ScrollViewProxy { get }
}
