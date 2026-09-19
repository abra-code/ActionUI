//
//  WindowRootSafeArea.swift
//  ActionUI
//

import SwiftUI

extension SwiftUI.View {
    /// Lets a window's ROOT `NavigationSplitView` reach the top of the window on macOS.
    ///
    /// On macOS 27 a split view in a window with a toolbar owns the titlebar strip above its
    /// columns: AppKit adds one `NSTitlebarBackgroundView` per column (carrying the
    /// scroll-edge-effect pocket) as a child of the `NSSplitView`, at the top of the split view's
    /// OWN bounds, and each column insets its content below its band. That is only right while the
    /// split view starts at the top of the window. Anywhere lower, the bands paint over the detail
    /// column's first ~52 points. (The sidebar escapes only because its wrapper draws above them.)
    /// The same layouts rendered correctly on macOS 26, and a pure SwiftUI `WindowGroup` shows it
    /// too, so this works around an OS bug rather than a hosting mistake.
    ///
    /// SwiftUI extends a split view under the titlebar by itself, but only while the split view
    /// touches the safe-area edge. The root element's own modifiers break that contact - a top
    /// padding of 4 points is enough - and the split view then stays below the titlebar. Ignoring
    /// the top safe area OUTSIDE those modifiers moves the padded root to the top of the window,
    /// and the split view extends the rest of the way from there. A side effect: the root's top
    /// padding ends up under the titlebar and no longer shows.
    ///
    /// Apply it to the root CONTENT, inside `WindowModalView`, not around it. Everything inside
    /// the ignoring view loses the top safe area, and the window-level toast overlay has to stay
    /// below the titlebar.
    ///
    /// Limits:
    /// - The window's content view must span the titlebar: `NSWindowStyleMaskFullSizeContentView`
    ///   in an AppKit host (a SwiftUI `WindowGroup` window always has it). Without it the top safe
    ///   area is zero, this is a no-op, and the bands still cover the detail column.
    /// - Only a split view AT THE ROOT is handled. Any other root keeps the safe area, since its
    ///   content has to stay below the titlebar. A split view nested inside other content (under a
    ///   header, in a tab) still gets the bands painted over it on macOS 27; nothing here can
    ///   reach that case.
    /// - A root top padding larger than the titlebar leaves the split view below the titlebar, and
    ///   the bands cover its content again.
    ///
    /// macOS only: elsewhere the top safe area is the status bar / notch, which must be kept.
    @ViewBuilder
    func windowRootSafeArea(rootElementType: String) -> some SwiftUI.View {
#if os(macOS)
        if rootElementType == "NavigationSplitView" {
            self.ignoresSafeArea(.container, edges: .top)
        } else {
            self
        }
#else
        self
#endif
    }
}
