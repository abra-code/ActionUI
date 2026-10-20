// SwiftUI rendering of Tab; its portable part is in Core/Elements/Tab.swift.

import SwiftUI

// Tab is not meant to be instantiated outside of TabView definition
// We only need the Tab as a distinct element to take adavantage of existing decoding infrastructure of children[] array in TabView
// Without it, we would need to add a lot of specialized code to load non-ActionUIElement type

extension Tab: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { _, _, _, _, logger in
        logger.log("Tab should not be constructed as a regular view. It is only used to build a tab in a TabView.", .error)
        return SwiftUI.EmptyView()
    }
}
