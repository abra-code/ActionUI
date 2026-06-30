// Add-ons/ActionUIChat/Sources/Markdown/MarkdownAttributedString.swift
//
// Builds ONE NSAttributedString for a whole chat message from the parsed Markdown model, so the
// message renders in a single native text view (NSTextView / UITextView) and the WHOLE message is
// selectable / copyable - unlike a stack of separate SwiftUI views, where selection is per-fragment
// (a table selects per cell, a list per line). The rendering is preserved: headings, emphasis, code,
// links, code blocks, block quotes, lists (with hanging indents), thematic breaks, and tables.
//
// Cross-platform: paragraph hanging indents (NSParagraphStyle.headIndent / tabStops), monospaced
// fonts, and bold/italic font traits all work on AppKit and UIKit. NSTextTable is AppKit-only, so
// tables are rendered as monospaced, space-padded columns (one code path, selectable everywhere).
//
// Spacing convention: "\n" ends a block (a paragraph, which carries paragraphSpacing for the gap),
// while U+2028 (LINE SEPARATOR) is an INTRA-block soft break - used inside code blocks and tables so
// the whole block is one paragraph with a single trailing gap rather than a gap after every line.

import Foundation

#if canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

enum MarkdownAttributed {
    static func attributedString(from blocks: [MarkdownBlock]) -> NSAttributedString {
        let builder = MarkdownAttributedBuilder()
        return builder.build(blocks)
    }
}

private final class MarkdownAttributedBuilder {

    private let storage = NSMutableAttributedString()

    // Fonts derived from the body text style, so the message honors Dynamic Type.
    private let bodyFont = PlatformFont.preferredFont(forTextStyle: .body)
    private lazy var baseSize = bodyFont.pointSize
    private lazy var monoFont = PlatformFont.monospacedSystemFont(ofSize: baseSize * 0.94, weight: .regular)

    private let labelColor = MarkdownColors.label
    private let secondaryColor = MarkdownColors.secondary
    private let linkColor = MarkdownColors.link
    private let codeBackground = MarkdownColors.codeFill
    private let separatorColor = MarkdownColors.separator

    private let indentStep: CGFloat = 22
    private let blockSpacing: CGFloat = 9
    private let listSpacing: CGFloat = 3

    func build(_ blocks: [MarkdownBlock]) -> NSAttributedString {
        appendBlocks(blocks, indent: 0, color: labelColor)
        // Drop the final block-terminating newline so the message has no trailing blank line.
        if storage.string.hasSuffix("\n") {
            storage.deleteCharacters(in: NSRange(location: storage.length - 1, length: 1))
        }
        return storage
    }

    // MARK: - Blocks

    private func appendBlocks(_ blocks: [MarkdownBlock], indent: CGFloat, color: PlatformColor) {
        for block in blocks {
            appendBlock(block, indent: indent, color: color)
        }
    }

    private func appendBlock(_ block: MarkdownBlock, indent: CGFloat, color: PlatformColor) {
        switch block {
        case .heading(let level, let inlines):
            appendHeading(level: level, inlines: inlines, indent: indent, color: color)
        case .paragraph(let inlines):
            let body = renderInlines(inlines, base: bodyFont, bold: false, italic: false, strike: false, link: nil, color: color)
            emit(body, style: blockStyle(indent: indent))
        case .codeBlock(_, let code):
            appendCodeBlock(code, indent: indent)
        case .blockQuote(let inner):
            // Quoted text is tinted secondary (links keep their accent color).
            appendBlocks(inner, indent: indent + indentStep, color: secondaryColor)
        case .list(let ordered, let start, _, let items):
            appendList(ordered: ordered, start: start, items: items, indent: indent, color: color)
        case .thematicBreak:
            appendThematicBreak(indent: indent)
        case .table(let headers, let alignments, let rows):
            appendTable(headers: headers, alignments: alignments, rows: rows, indent: indent)
        }
    }

    private func appendHeading(level: Int, inlines: [MarkdownInline], indent: CGFloat, color: PlatformColor) {
        let font = headingFont(level)
        let body = renderInlines(inlines, base: font, bold: true, italic: false, strike: false, link: nil, color: color)
        let style = blockStyle(indent: indent)
        style.paragraphSpacingBefore = blockSpacing * 0.6
        style.paragraphSpacing = blockSpacing * 0.5
        emit(body, style: style)
    }

    private func appendCodeBlock(_ code: String, indent: CGFloat) {
        // Code lines are one paragraph (U+2028 between them), so the block is one rectangle.
        let joined = code.components(separatedBy: "\n").joined(separator: "\u{2028}")
        #if canImport(AppKit)
        // The rounded background rectangle is PAINTED by MarkdownLayoutManager (a draw-only marker, so
        // it adds no block structure to the text / exported RTF - an NSTextBlock here would merge with
        // the adjacent NSTextTable on copy). The paragraph just insets the code text to sit inside it.
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent + 10
        style.headIndent = indent + 10
        style.tailIndent = -10
        style.paragraphSpacing = blockSpacing
        style.paragraphSpacingBefore = 2
        let para = NSMutableAttributedString(string: joined + "\n", attributes: [
            .font: monoFont, .foregroundColor: labelColor, .markdownCodeBlock: true,
        ])
        para.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: para.length))
        storage.append(para)
        #else
        // iOS / visionOS: NSTextBlock is unavailable, so fall back to a per-glyph background.
        let body = NSAttributedString(string: joined, attributes: [
            .font: monoFont, .foregroundColor: labelColor, .backgroundColor: codeBackground,
        ])
        emit(body, style: blockStyle(indent: indent + 8))
        #endif
    }

    private func appendThematicBreak(indent: CGFloat) {
        #if canImport(AppKit)
        // A thin full-width hairline (an HTML <hr>) PAINTED by MarkdownLayoutManager across this short
        // marker paragraph - draw-only, so it adds no block structure to the exported RTF.
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = blockSpacing
        style.paragraphSpacing = blockSpacing
        style.minimumLineHeight = 11
        style.maximumLineHeight = 11
        let para = NSMutableAttributedString(string: " \n", attributes: [
            .font: PlatformFont.systemFont(ofSize: 1), .markdownRule: true,
        ])
        para.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: para.length))
        storage.append(para)
        #else
        // iOS / visionOS: NSTextBlock is unavailable; approximate with a thin line of dashes.
        let rule = NSAttributedString(string: String(repeating: "\u{2500}", count: 24),
                                      attributes: [.font: bodyFont, .foregroundColor: secondaryColor])
        emit(rule, style: blockStyle(indent: indent))
        #endif
    }

    // MARK: - Lists

    private func appendList(ordered: Bool, start: Int, items: [[MarkdownBlock]], indent: CGFloat, color: PlatformColor) {
        for (offset, itemBlocks) in items.enumerated() {
            let marker = ordered ? "\(start + offset)." : "\u{2022}"
            appendListItem(itemBlocks, marker: marker, indent: indent, color: color)
        }
    }

    private func appendListItem(_ blocks: [MarkdownBlock], marker: String, indent: CGFloat, color: PlatformColor) {
        var markerUsed = false
        for block in blocks {
            switch block {
            case .paragraph(let inlines) where !markerUsed:
                markerUsed = true
                appendListLine(marker: marker, inlines: inlines, indent: indent, color: color)
            case .list(let ordered, let start, _, let nested):
                appendList(ordered: ordered, start: start, items: nested, indent: indent + indentStep, color: color)
            default:
                // Additional blocks in the item render at the content indent (no marker).
                appendBlock(block, indent: indent + indentStep, color: color)
            }
        }
        if !markerUsed {
            appendListLine(marker: marker, inlines: [], indent: indent, color: color)
        }
    }

    private func appendListLine(marker: String, inlines: [MarkdownInline], indent: CGFloat, color: PlatformColor) {
        let contentIndent = indent + indentStep
        let line = NSMutableAttributedString(
            string: marker + "\t",
            attributes: [.font: bodyFont, .foregroundColor: secondaryColor]
        )
        line.append(renderInlines(inlines, base: bodyFont, bold: false, italic: false, strike: false, link: nil, color: color))

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = contentIndent
        style.tabStops = [NSTextTab(textAlignment: .left, location: contentIndent)]
        style.paragraphSpacing = listSpacing
        emit(line, style: style)
    }

    // MARK: - Tables (monospaced, space-padded; cross-platform and selectable)

    private func appendTable(headers: [[MarkdownInline]], alignments: [MarkdownColumnAlignment],
                             rows: [[[MarkdownInline]]], indent: CGFloat) {
        #if canImport(AppKit)
        appendTableNative(headers: headers, alignments: alignments, rows: rows)
        #else
        appendTableMonospaced(headers: headers, alignments: alignments, rows: rows, indent: indent)
        #endif
    }

    #if canImport(AppKit)
    // Native bordered table via NSTextTable (macOS only): proportional content-sized columns, real
    // cell borders, per-column alignment, a tinted header row - all selectable as part of the one
    // text view. NSTextTable / NSTextTableBlock are AppKit-only, hence the monospaced fallback below.
    private func appendTableNative(headers: [[MarkdownInline]], alignments: [MarkdownColumnAlignment],
                                   rows: [[[MarkdownInline]]]) {
        let columns = max(headers.count, rows.map(\.count).max() ?? 0)
        if columns == 0 {
            return
        }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true

        let bodyRows: [([[MarkdownInline]], Bool)] = [(headers, true)] + rows.map { ($0, false) }
        for (rowIndex, entry) in bodyRows.enumerated() {
            let cells = entry.0
            let isHeader = entry.1
            for column in 0..<columns {
                let cellBlock = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1,
                                                 startingColumn: column, columnSpan: 1)
                cellBlock.setBorderColor(separatorColor)
                cellBlock.setWidth(1, type: .absoluteValueType, for: .border)
                cellBlock.setWidth(5, type: .absoluteValueType, for: .padding)
                if isHeader {
                    cellBlock.backgroundColor = codeBackground
                }
                let cellStyle = NSMutableParagraphStyle()
                cellStyle.textBlocks = [cellBlock]
                cellStyle.alignment = nsAlignment(alignments, column)
                let inlines = column < cells.count ? cells[column] : []
                let content = renderInlines(inlines, base: bodyFont, bold: isHeader, italic: false,
                                            strike: false, link: nil, color: labelColor)
                let cell = NSMutableAttributedString(attributedString: content)
                cell.append(NSAttributedString(string: "\n"))
                cell.addAttribute(.paragraphStyle, value: cellStyle, range: NSRange(location: 0, length: cell.length))
                storage.append(cell)
            }
        }
    }

    private func nsAlignment(_ alignments: [MarkdownColumnAlignment], _ index: Int) -> NSTextAlignment {
        let value = index < alignments.count ? alignments[index] : .none
        switch value {
        case .center:
            return .center
        case .right:
            return .right
        default:
            return .left
        }
    }
    #endif

    private func appendTableMonospaced(headers: [[MarkdownInline]], alignments: [MarkdownColumnAlignment],
                                       rows: [[[MarkdownInline]]], indent: CGFloat) {
        let headerText = headers.map(plainText)
        let rowTexts = rows.map { $0.map(plainText) }
        let columns = max(headerText.count, rowTexts.map(\.count).max() ?? 0)
        if columns == 0 {
            return
        }

        var widths = [Int](repeating: 0, count: columns)
        func note(_ cells: [String]) {
            for (index, cell) in cells.enumerated() where index < columns {
                widths[index] = max(widths[index], cell.count)
            }
        }
        note(headerText)
        rowTexts.forEach(note)

        func alignment(_ index: Int) -> MarkdownColumnAlignment {
            return index < alignments.count ? alignments[index] : .none
        }

        var lines: [String] = []
        lines.append(formatRow(headerText, widths: widths, alignment: alignment))
        lines.append(widths.map { String(repeating: "\u{2500}", count: $0) }.joined(separator: "\u{2500}\u{253C}\u{2500}"))
        for row in rowTexts {
            lines.append(formatRow(row, widths: widths, alignment: alignment))
        }

        let body = NSAttributedString(
            string: lines.joined(separator: "\u{2028}"),
            attributes: [.font: monoFont, .foregroundColor: labelColor]
        )
        emit(body, style: blockStyle(indent: indent))
    }

    private func formatRow(_ cells: [String], widths: [Int], alignment: (Int) -> MarkdownColumnAlignment) -> String {
        var rendered: [String] = []
        for index in 0..<widths.count {
            let cell = index < cells.count ? cells[index] : ""
            rendered.append(pad(cell, to: widths[index], alignment: alignment(index)))
        }
        return rendered.joined(separator: " \u{2502} ")
    }

    private func pad(_ s: String, to width: Int, alignment: MarkdownColumnAlignment) -> String {
        let deficit = max(0, width - s.count)
        switch alignment {
        case .right:
            return String(repeating: " ", count: deficit) + s
        case .center:
            let left = deficit / 2
            return String(repeating: " ", count: left) + s + String(repeating: " ", count: deficit - left)
        default:
            return s + String(repeating: " ", count: deficit)
        }
    }

    // MARK: - Inline

    private func renderInlines(_ nodes: [MarkdownInline], base: PlatformFont, bold: Bool, italic: Bool,
                              strike: Bool, link: URL?, color: PlatformColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for node in nodes {
            switch node {
            case .text(let s):
                out.append(run(s, font: styledFont(base, bold: bold, italic: italic), strike: strike, link: link, color: color))
            case .lineBreak:
                out.append(run("\u{2028}", font: base, strike: strike, link: link, color: color))
            case .code(let s):
                out.append(codeRun(s, strike: strike, link: link, color: color))
            case .emphasis(let children):
                out.append(renderInlines(children, base: base, bold: bold, italic: true, strike: strike, link: link, color: color))
            case .strong(let children):
                out.append(renderInlines(children, base: base, bold: true, italic: italic, strike: strike, link: link, color: color))
            case .strikethrough(let children):
                out.append(renderInlines(children, base: base, bold: bold, italic: italic, strike: true, link: link, color: color))
            case .link(let children, let url):
                out.append(renderInlines(children, base: base, bold: bold, italic: italic, strike: strike, link: URL(string: url) ?? link, color: color))
            }
        }
        return out
    }

    private func run(_ s: String, font: PlatformFont, strike: Bool, link: URL?, color: PlatformColor) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: link == nil ? color : linkColor,
        ]
        if strike {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link {
            attributes[.link] = link
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: s, attributes: attributes)
    }

    private func codeRun(_ s: String, strike: Bool, link: URL?, color: PlatformColor) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: link == nil ? color : linkColor,
            .backgroundColor: codeBackground,
        ]
        if strike {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link {
            attributes[.link] = link
        }
        return NSAttributedString(string: s, attributes: attributes)
    }

    // MARK: - Helpers

    private func emit(_ body: NSAttributedString, style: NSParagraphStyle) {
        let paragraph = NSMutableAttributedString(attributedString: body)
        paragraph.append(NSAttributedString(string: "\n"))
        paragraph.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))
        storage.append(paragraph)
    }

    private func blockStyle(indent: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.paragraphSpacing = blockSpacing
        return style
    }

    private func headingFont(_ level: Int) -> PlatformFont {
        let textStyle: PlatformFont.TextStyle
        switch level {
        case 1: textStyle = .title1
        case 2: textStyle = .title2
        case 3: textStyle = .title3
        case 4: textStyle = .headline
        default: textStyle = .subheadline
        }
        let scaled = PlatformFont.preferredFont(forTextStyle: textStyle)
        return styledFont(scaled, bold: true, italic: false)
    }

    private func styledFont(_ base: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
        #if canImport(AppKit)
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold {
            traits.insert(.bold)
        }
        if italic {
            traits.insert(.italic)
        }
        if traits.isEmpty {
            return base
        }
        let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
        #elseif canImport(UIKit)
        var traits = base.fontDescriptor.symbolicTraits
        if bold {
            traits.insert(.traitBold)
        }
        if italic {
            traits.insert(.traitItalic)
        }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
        #endif
    }

    private func plainText(_ nodes: [MarkdownInline]) -> String {
        var out = ""
        for node in nodes {
            switch node {
            case .text(let s):
                out += s
            case .code(let s):
                out += s
            case .lineBreak:
                out += " "
            case .emphasis(let c), .strong(let c), .strikethrough(let c):
                out += plainText(c)
            case .link(let c, _):
                out += plainText(c)
            }
        }
        return out
    }

}

// Cross-platform semantic colors (NSColor and UIColor name these members differently).
private enum MarkdownColors {
    static var label: PlatformColor {
        #if canImport(AppKit)
        return .labelColor
        #else
        return .label
        #endif
    }
    static var secondary: PlatformColor {
        #if canImport(AppKit)
        return .secondaryLabelColor
        #else
        return .secondaryLabel
        #endif
    }
    static var link: PlatformColor {
        #if canImport(AppKit)
        return .linkColor
        #else
        return .link
        #endif
    }
    static var codeFill: PlatformColor {
        #if canImport(AppKit)
        return .quaternaryLabelColor
        #else
        return .quaternarySystemFill
        #endif
    }
    static var separator: PlatformColor {
        #if canImport(AppKit)
        return .separatorColor
        #else
        return .separator
        #endif
    }
}
