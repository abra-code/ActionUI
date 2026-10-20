// SwiftUI rendering of HSplitView; its portable part is in Core/Elements/HSplitView.swift.

import SwiftUI

extension HSplitView: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]

#if os(macOS)
        // Read the first child's idealWidth from its frame properties to set initial divider position
        let initialPosition: CGFloat? = {
            guard let firstChild = children.first,
                  let childModel = windowModel?.viewModels[firstChild.id] else { return nil }
            let props = ActionUIRegistry.shared.currentProperties(element: firstChild, model: childModel)
            return BaseModifiers(props).frame?.idealWidth.map { CGFloat($0) }
        }()

        return SwiftUI.HSplitView {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                if let childModel = windowModel?.viewModels[child.id] {
                    if index == 0, let position = initialPosition {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                            .background(SplitViewInitialPositionSetter(position: position))
                    } else {
                        ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                    }
                }
            }
        }
#else
        // Fallback for non-macOS platforms: use HStack
        return SwiftUI.HStack(spacing: 0) {
            ForEach(children, id: \.id) { child in
                if let childModel = windowModel?.viewModels[child.id] {
                    ActionUIView(element: child, model: childModel, windowUUID: windowUUID)
                }
            }
        }
#endif
    }
}
