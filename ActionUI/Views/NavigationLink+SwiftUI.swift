// SwiftUI rendering of NavigationLink; its portable part is in Core/Elements/NavigationLink.swift.

import SwiftUI

extension NavigationLink: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in

        let props = Props(properties)
        let title = props.title

        // Form 1: destination view is provided inline with NavigationLink
        if let destination = element.subviews?["destination"] as? any ActionUIElementBase {
             return SwiftUI.NavigationLink(title) {
                  if let windowModel = ActionUIModel.shared.windowModels[windowUUID],
                   let childModel = windowModel.viewModels[destination.id] {
                    // A screen inside the enclosing stack like any other, so it carries that
                    // container's persistentToolbar too. Form 2's destinations are built by
                    // NavigationStack itself and handled there; this form is pushed straight
                    // from here, and without this it would be the one screen that loses them.
                    PersistentToolbar.onScreen(
                        ActionUIView(element: destination, model: childModel, windowUUID: windowUUID),
                        element: destination,
                        windowUUID: windowUUID
                    )
                }
              }
        }
        // Form 2: destinationViewId is provided and the views themselves will be in parent NavigationStack or NavigationSplitView
        else if let destinationViewId = Self.initialValue(model) as? Int {
            return SwiftUI.NavigationLink(title, value: destinationViewId)
        }
        else {
            return SwiftUI.NavigationLink(title, destination: SwiftUI.EmptyView())
        }
    }
}
