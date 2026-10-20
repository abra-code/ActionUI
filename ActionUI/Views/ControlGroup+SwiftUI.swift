// SwiftUI rendering of ControlGroup; its portable part is in Core/Elements/ControlGroup.swift.

import SwiftUI

extension ControlGroup: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let title = Props(properties).title
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
                
        if let title = title {
            return SwiftUI.ControlGroup(title) {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        } else {
            return SwiftUI.ControlGroup {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        }
    }
}
