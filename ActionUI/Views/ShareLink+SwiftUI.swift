// SwiftUI rendering of ShareLink; its portable part is in Core/Elements/ShareLink.swift.

import SwiftUI

extension ShareLink: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        guard let item = props.item, let url = URL(string: item) else {
            logger.log("ShareLink missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let subject = props.subject
        let message = props.message
        return SwiftUI.ShareLink(item: url, subject: SwiftUI.Text(subject ?? ""), message: SwiftUI.Text(message ?? ""))
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
