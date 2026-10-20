// SwiftUI rendering of ContentUnavailableView; its portable part is in Core/Elements/ContentUnavailableView.swift.

import SwiftUI

extension ContentUnavailableView: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)

        if props.search {
            let query = model.value as? String ?? props.query
            if query.isEmpty {
                return SwiftUI.ContentUnavailableView.search
            } else {
                return SwiftUI.ContentUnavailableView.search(text: query)
            }
        }

        let title = model.value as? String ?? props.title
        let description = props.description
        let systemImage = props.systemImage

        if let systemImage {
            if let description {
                return SwiftUI.ContentUnavailableView(title, systemImage: systemImage, description: SwiftUI.Text(description))
            } else {
                return SwiftUI.ContentUnavailableView(title, systemImage: systemImage)
            }
        } else {
            if let description {
                return SwiftUI.ContentUnavailableView {
                    SwiftUI.Label(title, systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleOnly)
                } description: {
                    SwiftUI.Text(description)
                }
            } else {
                return SwiftUI.ContentUnavailableView {
                    SwiftUI.Label(title, systemImage: "exclamationmark.triangle")
                        .labelStyle(.titleOnly)
                }
            }
        }
    }
}
