// SwiftUI rendering of EmptyView; its portable part is in Core/Elements/EmptyView.swift.

import SwiftUI

extension EmptyView: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }
    
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        return SwiftUI.EmptyView()
    }
}
