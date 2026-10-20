// SwiftUI rendering of ScrollView; its portable part is in Core/Elements/ScrollView.swift.

import SwiftUI

extension ScrollView: ActionUISwiftUIRenderer {
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
