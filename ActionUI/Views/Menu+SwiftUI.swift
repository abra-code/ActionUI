// SwiftUI rendering of Menu; its portable part is in Core/Elements/Menu.swift.

import SwiftUI

extension Menu: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        
        if let labelContent = element.subviews?["label"] as? any ActionUIElementBase {
            return SwiftUI.Menu {
                ForEach(children, id: \.id) { child in
                    if let childModel = windowModel?.viewModels[child.id] {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            } label: {
                if let labelModel = windowModel?.viewModels[labelContent.id] {
                    ActionUIView(element: labelContent, model: labelModel, windowUUID: windowUUID)
                }
            }
        }
        
        let title = Props(properties).title
        return SwiftUI.Menu(title) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
