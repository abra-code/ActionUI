// Sources/Views/ScrollView.swift
/*
 Sample JSON for ScrollView:
 {
   "type": "ScrollView",
   "id": 1,              // Optional: Non-zero positive integer for runtime programmatic interaction
   "content": {          // Required: Single child view or array of views. Note: Declared as a top-level key in JSON but stored in subviews["content"] by ActionUIElement.init(from:).
     "type": "Text", "properties": { "text": "Scrollable content" }
   },
   "properties": {
     "axis": "vertical",  // Optional: "vertical", "horizontal", or "both"; defaults to "vertical"
     "showsIndicators": true, // Optional: Boolean for scroll indicators, defaults to true
     "onRefreshActionID": "scroll.refresh" // Optional: String. When set, enables pull-to-refresh; fires this actionID on pull. The spinner stays until the client delivers fresh data to this view or anything inside it (any setElementRows/setElementValue/setElementState call targeting this view or a descendant), or a safety timeout elapses.
   }
   // Note: These properties are specific to ScrollView. Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity, cornerRadius, actionID, disabled) and additional View protocol modifiers are inherited and applied via ActionUIRegistry.shared.applyViewModifiers(to: baseView, properties: element.properties).
 }
*/

import SwiftUI

extension ScrollView {
    /// ScrollView's properties, parsed from the raw dictionary. Built at the start of every render.
    struct Props: Sendable {
        enum Axis: String, Sendable, CaseIterable {
            case vertical, horizontal, both
        }

        /// A name that is not one of the three, or no string, is vertical.
        var axis = Axis.vertical
        /// A value that is not a Bool is true.
        var showsIndicators = true
        /// When set, enables pull-to-refresh and names the action the pull fires.
        var onRefreshActionID: String?

        init(_ properties: [String: Any]) {
            axis = (properties["axis"] as? String).flatMap(Axis.init(rawValue:)) ?? .vertical
            showsIndicators = properties["showsIndicators"] as? Bool ?? true
            onRefreshActionID = properties["onRefreshActionID"] as? String
        }
    }
}

struct ScrollView: ActionUIViewConstruction {
    static var valueType: Any.Type = Void.self
    static var initialValue: (ViewModel) -> Any? = { model in model.value }
    static var initialStates: (ViewModel) -> [String: Any] = { model in model.states }
    static var parseStringValue: ((String, String?, any ActionUILogger) -> Any?)? = nil
    static var serializeValueToString: ((Any, String?, any ActionUILogger) -> String?)? = nil
    static var insertableContainers: [String: ContainerShape]? = nil

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let content = element.subviews?["content"] as? any ActionUIElementBase ?? ActionUIElement(id: ActionUIElement.generateNegativeID(), type: "EmptyView", properties: [:], subviews: nil)
        let props = Props(properties)
        let axes: Axis.Set = {
            switch props.axis {
            case .horizontal: return .horizontal
            case .both: return [.horizontal, .vertical]
            case .vertical: return .vertical
            }
        }()
        
        return SwiftUI.ScrollView(axes, showsIndicators: props.showsIndicators) {
            if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
               let childModel = windowModel.viewModels[content.id] {
                ActionUIView(element: content, model: childModel, windowUUID: windowUUID)
            } else {
                SwiftUI.EmptyView()
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, element, windowUUID, properties, logger in
        var modifiedView = view
        let props = Props(properties)
        modifiedView = modifiedView.scrollIndicators(props.showsIndicators ? .automatic : .hidden)
        if let onRefreshActionID = props.onRefreshActionID {
            let viewID = element.id
            modifiedView = modifiedView.refreshable {
                await ActionUIModel.shared.runRefresh(windowUUID: windowUUID, viewID: viewID, actionID: onRefreshActionID)
            }
        }
        return modifiedView
    }
}
