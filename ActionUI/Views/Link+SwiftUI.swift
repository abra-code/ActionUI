// SwiftUI rendering of Link; its portable part is in Core/Elements/Link.swift.

import SwiftUI

extension Link: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        guard let urlString = props.url, let url = URL(string: urlString) else {
            logger.log("Link missing valid URL, returning EmptyView", .warning)
            return SwiftUI.EmptyView()
        }
        let title = props.title
        
        return SwiftUI.Link(destination: url) {
            SwiftUI.Text(title)
        }
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, properties, logger in
        return view
    }
}
