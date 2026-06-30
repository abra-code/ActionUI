// Add-ons/ActionUIChat/Sources/Markdown/MessageTextView.swift
//
// A SwiftUI wrapper around ONE native text view (NSTextView on macOS, UITextView on iOS / visionOS)
// that renders a whole chat message's NSAttributedString. Because it is a single text view, the entire
// message is selectable and copyable as one unit (the reason for moving off a stack of SwiftUI views).
// The text view is read-only but selectable, draws no background (the bubble behind it provides that),
// does not scroll (it self-sizes to its content for the proposed width), and handles links natively.
//
// Self-sizing: SwiftUI proposes a width; `sizeThatFits` lays the text out in a container of that width
// and returns the used height, so the view participates in the transcript's vertical stack correctly.

import SwiftUI

#if canImport(AppKit)
import AppKit

// Draw-only decorations: a code block's rounded background and a thematic break's hairline are PAINTED
// by the layout manager rather than baked into the text model. This keeps copied RTF clean - an
// NSTextBlock is a one-cell table in RTF, so a code-block NSTextBlock adjacent to a real NSTextTable
// would merge on copy (preceding text lands inside the table). These markers carry no block structure,
// so only genuine tables remain tables in the exported RTF.
extension NSAttributedString.Key {
    static let markdownCodeBlock = NSAttributedString.Key("ActionUIChat.codeBlock")
    static let markdownRule = NSAttributedString.Key("ActionUIChat.rule")
}

final class MarkdownLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)   // inline-code backgrounds, table cells
        guard let storage = textStorage, let container = textContainers.first else {
            return
        }
        let width = container.size.width
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.markdownCodeBlock, in: charRange) { value, range, _ in
            guard value != nil else {
                return
            }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            rect.origin.x = origin.x + 1
            rect.size.width = width - 2
            let card = rect.insetBy(dx: 0, dy: -3)
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: card, xRadius: 6, yRadius: 6).fill()
        }

        storage.enumerateAttribute(.markdownRule, in: charRange) { value, range, _ in
            guard value != nil else {
                return
            }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            let y = rect.midY.rounded() + 0.5
            NSColor.separatorColor.setStroke()
            let line = NSBezierPath()
            line.lineWidth = 1
            line.move(to: NSPoint(x: origin.x + 1, y: y))
            line.line(to: NSPoint(x: origin.x + width - 1, y: y))
            line.stroke()
        }
    }
}

struct MessageTextView: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSTextView {
        // Build an explicit TextKit 1 stack with the custom layout manager. (TextKit 1 is also required
        // for NSTextTable, which the attributed string uses for real tables.)
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.textStorage?.isEqual(to: attributed) == false {
            textView.textStorage?.setAttributedString(attributed)
            textView.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layoutManager = nsView.layoutManager else {
            return nil
        }
        let width = proposal.width ?? container.containerSize.width
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let height = layoutManager.usedRect(for: container).height
        return CGSize(width: width, height: ceil(height))
    }
}

#elseif canImport(UIKit)
import UIKit

struct MessageTextView: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.linkTextAttributes = [.foregroundColor: UIColor.link]
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.attributedText != attributed {
            textView.attributedText = attributed
            textView.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }
}
#endif
