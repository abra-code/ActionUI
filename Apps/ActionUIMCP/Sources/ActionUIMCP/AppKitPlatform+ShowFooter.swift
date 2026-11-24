// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// AppKitPlatform+ShowFooter.swift - the bottom bar of a `show` window: where the content came from
// (a file, with a button that shows it in the Finder, or a web address) and when the window was
// shown. It is AppKit, outside the ActionUI JSON, so the agent can neither change it nor press its
// button; it keeps working in a kept window after the session ends.

#if canImport(AppKit)
import AppKit

final class ShowFooterView: NSView {
    static let height: CGFloat = 26

    private let path: String?

    init(footer: ShowFooter) {
        path = footer.path
        super.init(frame: .zero)

        let separator = NSBox()
        separator.boxType = .separator

        var items: [NSView] = []
        if let source = footer.path ?? footer.url {
            // A line break in a file name would make the label taller than the bar and draw it over
            // the content, and a direction override (U+202A-202E, U+2066-2069) could make
            // "x<RLO>txt.app" read as a text file: these show as "?", as ls shows control characters.
            let shownSource = String(String.UnicodeScalarView(source.unicodeScalars.map { scalar in
                if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) { return "?" }
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator: return "?"
                default: return scalar
                }
            }))
            let label = Self.label(shownSource)
            label.lineBreakMode = .byTruncatingMiddle
            label.isSelectable = true
            label.toolTip = source
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            items.append(label)
        }
        if footer.path != nil {
            let reveal = NSButton(image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Show in Finder") ?? NSImage(),
                                  target: self, action: #selector(revealInFinder))
            reveal.isBordered = false
            reveal.imageScaling = .scaleProportionallyDown
            reveal.toolTip = "Show in Finder"
            reveal.setAccessibilityLabel("Show in Finder")
            items.append(reveal)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        items.append(spacer)
        let shown = Self.label(footer.shownAt.formatted(date: .abbreviated, time: .shortened))
        shown.toolTip = "When the window was shown"
        shown.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        items.append(shown)

        let row = NSStackView(views: items)
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        for view in [separator, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // Views do not clip to their bounds, and the rectangle asked for can be the whole window.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.intersection(dirtyRect).fill()
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Selects the file in a Finder window; never opens it. A file that is gone gets a beep.
    @objc private func revealInFinder() {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
#endif
