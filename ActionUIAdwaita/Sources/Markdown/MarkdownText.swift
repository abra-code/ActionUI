// Sources/Markdown/MarkdownText.swift
/*
 Markdown as SwiftUI's Text shows it, for Text on GTK. The source is parsed with RichText's parser
 (copied into Markdown/RichText by Scripts/sync-richtext-markdown.sh), which follows Apple's parser
 (cmark-gfm, behind AttributedString(markdown:)) for common input. The document becomes an
 AttributedString with the same characters Apple's has, and the GtkLabel draws it from Pango markup.

 - Inline styles only, as SwiftUI's Text draws: bold, italic, strikethrough, code (monospaced) and
   links, autolinks included. Blocks run together with no separator, as in Apple's
   AttributedString(markdown:): a soft line break is a space, a hard one a new line, a code block
   keeps its text and ends in a new line, a thematic break is U+2E3B, an image shows its alt text.
 - FoundationEssentials has the link attribute but not Apple's inlinePresentationIntent, so the
   styles are an attribute of ActionUI's own (MarkdownStyleAttribute).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The inline styles of markdown text.
struct MarkdownStyle: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let bold = MarkdownStyle(rawValue: 1 << 0)
    static let italic = MarkdownStyle(rawValue: 1 << 1)
    static let strikethrough = MarkdownStyle(rawValue: 1 << 2)
    static let code = MarkdownStyle(rawValue: 1 << 3)
}

/// The attribute that carries a run's MarkdownStyle.
enum MarkdownStyleAttribute: AttributedStringKey {
    typealias Value = MarkdownStyle
    static let name = "ActionUI.markdownStyle"
}

enum MarkdownText {
    /// The markdown as the AttributedString SwiftUI's Text shows.
    static func attributedString(markdown: String) -> AttributedString {
        var result = AttributedString()
        append(RichTextMarkdownParser.parse(markdown), to: &result)
        return result
    }

    private static func append(_ blocks: [RichTextBlock], to result: inout AttributedString) {
        for block in blocks {
            switch block {
            case .heading(_, let inlines), .paragraph(let inlines):
                append(inlines, style: [], link: nil, to: &result)
            case .codeBlock(_, let code):
                result.append(AttributedString(code.hasSuffix("\n") ? code : code + "\n"))
            case .blockQuote(let children):
                append(children, to: &result)
            case .list(_, _, _, let items):
                for item in items {
                    append(item, to: &result)
                }
            case .thematicBreak:
                result.append(AttributedString("\u{2E3B}"))
            case .table(let headers, _, let rows):
                for cell in headers {
                    append(cell, style: [], link: nil, to: &result)
                }
                for row in rows {
                    for cell in row {
                        append(cell, style: [], link: nil, to: &result)
                    }
                }
            }
        }
    }

    private static func append(_ inlines: [RichTextInline], style: MarkdownStyle, link: URL?,
                               to result: inout AttributedString) {
        func run(_ text: String, _ style: MarkdownStyle) {
            var piece = AttributedString(text)
            if !style.isEmpty {
                piece[MarkdownStyleAttribute.self] = style
            }
            piece.link = link
            result.append(piece)
        }
        for inline in inlines {
            switch inline {
            case .text(let text):
                run(text, style)
            case .emphasis(let children):
                append(children, style: style.union(.italic), link: link, to: &result)
            case .strong(let children):
                append(children, style: style.union(.bold), link: link, to: &result)
            case .strikethrough(let children):
                append(children, style: style.union(.strikethrough), link: link, to: &result)
            case .code(let code):
                run(code, style.union(.code))
            case .link(let text, let url):
                append(text, style: style, link: URL(string: url) ?? link, to: &result)
            case .image(let alt, _):
                run(alt, style)
            case .lineBreak:
                run("\n", style)
            }
        }
    }

    /// Pango markup for the GtkLabel, with GtkLabel's <a href> for links; nil when no run has a
    /// style or a link, so the label shows the plain text.
    static func pangoMarkup(_ attributed: AttributedString) -> String? {
        let runs = attributed.runs
        guard runs.contains(where: { $0.link != nil || !($0[MarkdownStyleAttribute.self] ?? []).isEmpty }) else {
            return nil
        }
        var markup = ""
        var openLink: URL?
        for run in runs {
            if run.link != openLink {
                if openLink != nil {
                    markup += "</a>"
                }
                if let link = run.link {
                    markup += "<a href=\"" + escaped(link.absoluteString) + "\">"
                }
                openLink = run.link
            }
            var text = escaped(String(attributed[run.range].characters))
            let style = run[MarkdownStyleAttribute.self] ?? []
            if style.contains(.code) {
                text = "<tt>" + text + "</tt>"
            }
            if style.contains(.strikethrough) {
                text = "<s>" + text + "</s>"
            }
            if style.contains(.italic) {
                text = "<i>" + text + "</i>"
            }
            if style.contains(.bold) {
                text = "<b>" + text + "</b>"
            }
            markup += text
        }
        if openLink != nil {
            markup += "</a>"
        }
        return markup
    }

    /// The text escaped for markup, as g_markup_escape_text escapes it: the five XML characters,
    /// and the control characters GMarkup takes only as character references.
    static func escaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default:
                let value = scalar.value
                if (value >= 0x1 && value <= 0x8) || value == 0xB || value == 0xC || (value >= 0xE && value <= 0x1F)
                    || (value >= 0x7F && value <= 0x84) || (value >= 0x86 && value <= 0x9F) {
                    result += "&#x" + String(value, radix: 16) + ";"
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
