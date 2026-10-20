// SwiftUI rendering of AsyncImage; its portable part is in Core/Elements/AsyncImage.swift.

import SwiftUI

extension AsyncImage: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let urlString = Self.initialValue(model) as? String
        let props = Props(properties)
        let placeholder = props.placeholder
        let resizable = props.resizable

        let contentMode: ContentMode
        switch props.contentMode {
        case .fit: contentMode = .fit
        case .fill: contentMode = .fill
        }

        guard let urlString = urlString, let url = URL(string: urlString) else {
            logger.log("AsyncImage missing valid url, using placeholder '\(placeholder)'", .warning)
            return SwiftUI.Image(systemName: placeholder)
        }

        return SwiftUI.AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                if resizable {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    image
                }
            case .failure, .empty:
                SwiftUI.Image(systemName: placeholder)
            @unknown default:
                SwiftUI.Image(systemName: placeholder)
            }
        }
    }
}
