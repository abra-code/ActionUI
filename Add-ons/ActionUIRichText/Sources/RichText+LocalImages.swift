// Add-ons/ActionUIRichText/Sources/RichText+LocalImages.swift
//
// Local (file:) images in the element's Markdown, as the trust policy allows: the RichText package reads a
// file: image as given, so the element asks ActionUI first, as the built-in Image does for its file, and a
// refused image keeps its alt text but loses its address, which draws it as an image that cannot be loaded.
// The same on Apple platforms and Linux.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import RichText

extension RichTextDocument {
    /// The document with every file: image whose path `reads` refuses left without an address. Other
    /// images (web, data, and addresses the package refuses itself) are kept as they are.
    func keepingLocalImages(where reads: (String) -> Bool) -> RichTextDocument {
        RichTextDocument(blocks: blocks.map { $0.keepingLocalImages(where: reads) })
    }
}

extension RichTextBlock {
    func keepingLocalImages(where reads: (String) -> Bool) -> RichTextBlock {
        switch self {
        case .heading(let level, let inlines):
            return .heading(level: level, inlines.keepingLocalImages(where: reads))
        case .paragraph(let inlines):
            return .paragraph(inlines.keepingLocalImages(where: reads))
        case .blockQuote(let blocks):
            return .blockQuote(blocks.map { $0.keepingLocalImages(where: reads) })
        case .list(let ordered, let start, let tight, let items):
            return .list(ordered: ordered, start: start, tight: tight,
                         items: items.map { $0.map { $0.keepingLocalImages(where: reads) } })
        case .table(let headers, let alignments, let rows):
            return .table(headers: headers.map { $0.keepingLocalImages(where: reads) }, alignments: alignments,
                          rows: rows.map { $0.map { $0.keepingLocalImages(where: reads) } })
        case .codeBlock, .thematicBreak:
            return self
        }
    }
}

extension Array where Element == RichTextInline {
    func keepingLocalImages(where reads: (String) -> Bool) -> [RichTextInline] {
        map { $0.keepingLocalImages(where: reads) }
    }
}

extension RichTextInline {
    func keepingLocalImages(where reads: (String) -> Bool) -> RichTextInline {
        switch self {
        case .image(let alt, let url):
            // The path the package would read: a file: URL's, percent escapes decoded.
            guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "file" else {
                return self
            }
            return reads(parsed.path) ? self : .image(alt: alt, url: "")
        case .emphasis(let children):
            return .emphasis(children.keepingLocalImages(where: reads))
        case .strong(let children):
            return .strong(children.keepingLocalImages(where: reads))
        case .strikethrough(let children):
            return .strikethrough(children.keepingLocalImages(where: reads))
        case .link(let text, let url):
            return .link(text: text.keepingLocalImages(where: reads), url: url)
        case .text, .code, .lineBreak:
            return self
        }
    }
}
