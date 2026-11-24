// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform+HazardStrip.swift - the yellow and black mark under the title bar of every
// actionui-mcp window, which shows it is a window an agent asked for: a strip on `show` windows, a
// thin striped line on the others. It is AppKit, outside the SwiftUI view that shows the ActionUI
// JSON, so nothing the agent writes can remove or restyle it.

#if canImport(AppKit)
import AppKit
import SwiftUI

/// A yellow band, bright at the top and darker at the bottom like a bent plastic tape, with black
/// notches along its top edge that lean like a backslash; as a line, black stripes across its whole
/// height, as far apart as the strip's notches. Drawn for its current width, so it follows the
/// window as it resizes.
final class HazardStripView: NSView {
    static let stripHeight: CGFloat = 12
    static let lineHeight: CGFloat = 3
    // The notches in proportion to the strip's height; the line's stripes have the same width and spacing.
    private static let notchDepth = stripHeight * 0.4
    private static let notchWidth = stripHeight * 0.8
    private static let notchSpacing = stripHeight * 2.1
    // The yellow, shared with the bottom bar of `show` windows.
    static let bright = NSColor(srgbRed: 252 / 255, green: 240 / 255, blue: 97 / 255, alpha: 1)
    static let dark = NSColor(srgbRed: 216 / 255, green: 185 / 255, blue: 74 / 255, alpha: 1)
    private static let notchColor = NSColor(srgbRed: 0.03, green: 0.03, blue: 0.035, alpha: 1)

    static func height(of mark: WindowMark) -> CGFloat {
        switch mark {
        case .strip: stripHeight
        case .line: lineHeight
        }
    }

    private let mark: WindowMark

    init(mark: WindowMark) {
        self.mark = mark
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Views do not clip to their bounds, and the notches at either end reach past them.
        bounds.clip()
        // The view is flipped, so angle 90 runs from the top (starting color) to the bottom.
        NSGradient(starting: Self.bright, ending: Self.dark)?.draw(in: bounds, angle: 90)

        let depth = mark == .strip ? Self.notchDepth : bounds.height  // 45 degrees: as far across as down
        Self.notchColor.setFill()
        let notches = NSBezierPath()
        var x = -depth - Self.notchSpacing
        while x < bounds.maxX {
            notches.move(to: NSPoint(x: x, y: 0))
            notches.line(to: NSPoint(x: x + Self.notchWidth, y: 0))
            notches.line(to: NSPoint(x: x + depth + Self.notchWidth, y: depth))
            notches.line(to: NSPoint(x: x + depth, y: depth))
            notches.close()
            x += Self.notchSpacing
        }
        notches.fill()
    }
}

extension AppKitPlatform {
    /// The window's content view: the mark on top, `content` below it, and for a `show` window its
    /// bottom bar under that.
    static func markedContainer(around content: NSView, mark: WindowMark, footer: ShowFooter?, windowID: String) -> NSView {
        // A hosting view that is not the window's content view does not pass its toolbar items and
        // navigation title on to the window unless asked: without this, an ActionUI toolbar is lost.
        (content as? NSHostingView<AnyView>)?.sceneBridgingOptions = [.toolbars, .title]
        let strip = HazardStripView(mark: mark)
        let bar = footer.map { ShowFooterView(footer: $0, windowID: windowID, content: content) }
        let container = NSView()
        for view in [strip, content] + (bar.map { [$0] } ?? []) {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        var constraints = [
            strip.topAnchor.constraint(equalTo: container.topAnchor),
            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: HazardStripView.height(of: mark)),
            content.topAnchor.constraint(equalTo: strip.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ]
        if let bar {
            constraints += [
                content.bottomAnchor.constraint(equalTo: bar.topAnchor),
                bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bar.heightAnchor.constraint(equalToConstant: ShowFooterView.height),
            ]
        } else {
            constraints.append(content.bottomAnchor.constraint(equalTo: container.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    /// A content size for the ActionUI content, grown by the mark and the bottom bar.
    static func withChrome(_ size: NSSize, _ mark: WindowMark, _ footer: ShowFooter?) -> NSSize {
        let bar = footer == nil ? 0 : ShowFooterView.height
        return NSSize(width: size.width, height: size.height + HazardStripView.height(of: mark) + bar)
    }
}
#endif
