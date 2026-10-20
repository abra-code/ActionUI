// SwiftUI rendering of ToolbarItemGroup; its portable part is in Core/Elements/ToolbarItemGroup.swift.

import SwiftUI

extension ToolbarItemGroup: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    // ToolbarItemGroup is never rendered standalone — buildView returns EmptyView.
    // Content is rendered inside ToolbarModifierView as part of the parent view's .toolbar modifier.
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, _ in
        SwiftUI.EmptyView()
    }
}
