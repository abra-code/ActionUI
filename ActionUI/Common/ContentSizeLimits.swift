// Common/ContentSizeLimits.swift

import SwiftUI

#if canImport(AppKit)
import AppKit

/// The size limits a window's SwiftUI content reports: `minSize` for a zero
/// size proposal, `maxSize` for an (effectively) infinite one. Content with a
/// fixed root frame reports minSize == maxSize; flexible axes report a very
/// large maxSize component.
public struct ContentSizeLimits {
    public let minSize: CGSize
    public let maxSize: CGSize
}

@MainActor
extension ActionUIModel {
    /// Measures the size limits of a window's loaded root element.
    ///
    /// The measurement deliberately bypasses the window-level wrapper that
    /// FileLoadableView/RemoteLoadableView attach for content views
    /// (WindowModalView): its toast overlay anchoring expands to fill any
    /// proposal, so probing the wrapped view would report an unbounded maximum
    /// for every document. The bare root element view is built here instead and
    /// probed with a zero and an infinite proposal.
    ///
    /// An AppKit client hosting an ActionUI window can apply the result as the
    /// window's contentMinSize/contentMaxSize, and treat minSize == maxSize as
    /// a fixed-size (non-user-resizable) window.
    /// - Parameter windowUUID: Unique identifier of a window whose description has been loaded.
    /// - Returns: The content's size limits, or nil when the window or its root element is unknown.
    public func contentSizeLimits(windowUUID: String) -> ContentSizeLimits? {
        guard let windowModel = windowModels[windowUUID],
              let element = windowModel.element,
              let viewModel = windowModel.viewModels[element.id] else {
            return nil
        }
        let bareRootView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let hosting = NSHostingController(rootView: AnyView(bareRootView))
        let minSize = hosting.sizeThatFits(in: .zero)
        let maxSize = hosting.sizeThatFits(
            in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        return ContentSizeLimits(minSize: minSize, maxSize: maxSize)
    }
}
#endif
