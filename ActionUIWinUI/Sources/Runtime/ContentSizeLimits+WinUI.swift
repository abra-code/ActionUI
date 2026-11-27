// Sources/Runtime/ContentSizeLimits+WinUI.swift
/*
 The size limits of a window's content on Windows, the counterpart of Apple's (ActionUI/Common/
 ContentSizeLimits.swift) and Linux's (ActionUIAdwaita/Sources/Runtime/ContentSizeLimits+Adwaita.swift), which
 the remote server's actionui.contentSizeLimits answers with. As on Linux, it measures the content of a window
 on screen, whose controls have their styles (a TextField measured before its window loads is a pixel tall:
 WinUIWindow.fit): the bare root element, without the window's toolbar, as Apple measures the root element
 without its window wrapper. A window that is not on screen with its content loaded has none (nil, which the
 method answers as null).

 - minSize: the root's smallest size, as a stack reads a child's (WinUIObject.measureRequested, past WinUI's cap
   at the size offered): the width with nothing offered across, and the height with nothing offered down at the
   width the maximum height is measured at (below). A Text that wraps is taller than that when narrower, which
   one pair cannot say (Linux's note); a WinUI window does not enforce it as it is resized.
 - maxSize: the largest size, SwiftUI's size for an infinite proposal as the layout gives it: the natural size
   in an axis where the root does not expand, its frame's cap where it does, and
   Double.greatestFiniteMagnitude, which is what Apple reports, where nothing bounds it. The height is for the
   largest width, or for the natural width when nothing bounds the width.

 A fixed root frame gives minSize == maxSize, which a host reads as a window of a fixed size. The measures are
 WinUI's own, made outside its layout pass; the root is measured again for its window's size afterwards.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

/// The size limits of a window's content. Apple's has CGSize members; these have the same names, so
/// code reading `limits.minSize.width` builds on every platform.
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
    /// The size limits of the content of the window showing `windowUUID`, or nil when no such window is on
    /// screen with its content.
    public func contentSizeLimits(windowUUID: String) -> ContentSizeLimits? {
        guard let root = WinUIWindow.shownRoot(windowUUID: windowUUID), let view = root.outerView else {
            return nil
        }
        func measure() -> ContentSizeLimits {
            defer {
                // Measured here for other sizes: laid out again for its window's.
                view.invalidateMeasure()
            }
            let unbounded = Double.infinity
            let natural = view.measureRequested(ActionUIWinUISize(width: unbounded, height: unbounded))
            // Probed with nothing offered only along an axis the root can be made smaller in, or grows in (down to its
            // frame's minimum); elsewhere at its natural size, as a stack reads a child that cannot shrink: WinUI caps a
            // control's answer at what it is offered.
            let minWidth = root.compression.union(root.expansion).contains(.horizontal)
                ? view.measureRequested(ActionUIWinUISize(width: 0, height: unbounded)).width : natural.width
            let maxWidth: Double? = root.expansion.contains(.horizontal)
                ? root.caps.horizontal.map(Double.init) : natural.width
            // Both heights at one width, so that the minimum is not above the maximum.
            let heightForWidth = maxWidth ?? natural.width
            let minHeight = view.measureRequested(ActionUIWinUISize(width: heightForWidth,
                                                                   height: root.compression.union(root.expansion).contains(.vertical) ? 0 : unbounded)).height
            let maxHeight: Double? = root.expansion.contains(.vertical)
                ? root.caps.vertical.map(Double.init)
                : view.measureRequested(ActionUIWinUISize(width: heightForWidth, height: unbounded)).height
            func finite(_ value: Double) -> Double {
                value.isFinite ? max(0, value) : 0
            }
            return ContentSizeLimits(
                minSize: .init(width: finite(minWidth), height: finite(minHeight)),
                maxSize: .init(width: maxWidth.map(finite) ?? .greatestFiniteMagnitude,
                               height: maxHeight.map(finite) ?? .greatestFiniteMagnitude))
        }
        // The panel's own offer and answer kept for the window's next layout pass, which grows the window
        // when the answer changed for the same offer (LayoutPanel.measuringOutsideLayout).
        return view.layoutPanel?.measuringOutsideLayout(measure) ?? measure()
    }
}
