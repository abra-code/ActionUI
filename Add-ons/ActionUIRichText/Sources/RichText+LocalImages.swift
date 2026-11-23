// Add-ons/ActionUIRichText/Sources/RichText+LocalImages.swift
//
// The images in the element's Markdown: relative paths resolved against the "baseURL" property, the
// Markdown's own location; and local (file:) images as the trust policy allows. The RichText package reads a
// file: image as given, so the element asks ActionUI first, as the built-in Image does for its file, and a
// refused image keeps its alt text but loses its address, which draws it as an image that cannot be loaded.
// The same on Apple platforms and Linux.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import RichText

extension RichTextView {
    /// The "baseURL" property: where the Markdown lives, so its relative image paths (`logo.png`,
    /// `img/a.png`, `../../logo.png`) can be found. A path, of the Markdown file or of its folder, or a
    /// file:, http: or https: address (a folder's ends in "/"); nil when absent, empty or of another scheme.
    static func markdownBaseURL(_ value: Any?) -> URL? {
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        if let url = URL(string: string), let scheme = url.scheme?.lowercased() {
            return ["file", "http", "https"].contains(scheme) ? url : nil
        }
        // A path: an existing folder's gets its "/", to resolve against itself rather than its parent. Asked
        // with links followed (a .checkFileSystem hint does not follow one, so a link to a folder would not).
        let url = URL(filePath: string)
        #if canImport(Darwin)
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let folder = exists && isFolder.boolValue
        #else
        var isFolder = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let folder = exists && isFolder
        #endif
        return folder ? URL(filePath: string, directoryHint: .isDirectory) : url
    }

    /// The Markdown parsed, its relative image paths resolved against `baseURL`, and its local images kept
    /// as `reads` allows (keepingLocalImages): resolved first, so a path that leaves the Markdown's folder
    /// is asked about like any other.
    static func document(markdown: String, baseURL: URL?, reads: (String) -> Bool) -> RichTextDocument {
        let parsed = RichTextDocument(markdown: markdown)
        let resolved = baseURL.map { parsed.resolvingImageURLs(against: $0) } ?? parsed
        return resolved.keepingLocalImages(where: reads)
    }
}

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
