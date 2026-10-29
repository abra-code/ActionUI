// Sources/Runtime/ContentSizeLimits+Adwaita.swift
/*
 The size limits of a window's content on Linux, the counterpart of Apple's (ActionUI/Common/
 ContentSizeLimits.swift), which asks SwiftUI for the bare root element's size for a zero and for
 an infinite proposal. GTK sizes a widget only once it is in a window, where its styles apply, so
 this measures the content of a window on screen, without the window's header bar and toast
 overlay, as Apple measures the root element without its window wrapper; a window that is not on
 screen has none.

 - minSize: GTK's minimum: the minimum width, and the minimum height at the width the maximum
   height is measured at (below). Not SwiftUI's zero proposal, which compresses a Text to nothing:
   GTK never makes a label smaller than its minimum. Content whose height depends on its width
   (text that wraps) is taller than that when narrower, which the window enforces as it is
   resized; one pair cannot say so, and the height at the minimum width would exceed the
   maximum height (a Text: 106 high at 18 wide, 18 at its natural width), where Apple's minimum
   never exceeds its maximum.
 - maxSize: the content's largest size, SwiftUI's size for an infinite proposal as the layout
   reproduces it (LayoutCaps.largestSize): its natural size in an axis where it does not expand,
   its cap where it does, and Double.greatestFiniteMagnitude, which is what Apple reports, where
   nothing bounds it. The height is for the largest width, or for the natural width when nothing
   bounds the width.

 A fixed root frame gives minSize == maxSize on both platforms, which a host reads as a window of
 a fixed size.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

/// The size limits of a window's content (see above). Apple's has CGSize members; these have the
/// same names, so code reading `limits.minSize.width` builds on both.
public struct ContentSizeLimits: Sendable, Equatable {
    public struct Size: Sendable, Equatable {
        public let width: Double
        public let height: Double
    }

    public let minSize: Size
    public let maxSize: Size
}

@MainActor
extension ActionUIModel {
    /// The size limits of the content of the window showing `windowUUID`, or nil when no such
    /// window is on screen with its document.
    public func contentSizeLimits(windowUUID: String) -> ContentSizeLimits? {
        guard let content = AdwaitaApplication.shared.contentWidget(windowUUID) else {
            return nil
        }
        let widget = Gtk.Widget(content)
        let width = widget.measure(GTK_ORIENTATION_HORIZONTAL)
        let maxWidth = LayoutCaps.largestSize(content, GTK_ORIENTATION_HORIZONTAL)
        // Both heights at one width, so that the minimum is not above the maximum.
        let heightForWidth = maxWidth ?? width.natural
        let minHeight = widget.measure(GTK_ORIENTATION_VERTICAL, forSize: heightForWidth).minimum
        let maxHeight = LayoutCaps.largestSize(content, GTK_ORIENTATION_VERTICAL, forSize: heightForWidth)
        return ContentSizeLimits(
            minSize: .init(width: Double(width.minimum), height: Double(minHeight)),
            maxSize: .init(width: maxWidth.map(Double.init) ?? .greatestFiniteMagnitude,
                           height: maxHeight.map(Double.init) ?? .greatestFiniteMagnitude))
    }
}
