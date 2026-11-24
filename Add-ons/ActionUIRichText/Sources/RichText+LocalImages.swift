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
    /// `mayProbe` says whether the content may read a path, which is then asked whether it is a folder (on
    /// Windows the node's readsLocalFile; elsewhere every path is asked, as before).
    static func markdownBaseURL(_ value: Any?, mayProbe: (String) -> Bool = { _ in true }) -> URL? {
        guard let string = value as? String, !string.isEmpty else {
            return nil
        }
        if let url = URL(string: string), let scheme = url.scheme?.lowercased() {
            #if os(Windows)
            // "C:\docs\notes.md" reads as a URL whose scheme is "c": on Windows a one-letter scheme is a drive.
            if scheme.count != 1 {
                return ["file", "http", "https"].contains(scheme) ? url : nil
            }
            #else
            return ["file", "http", "https"].contains(scheme) ? url : nil
            #endif
        }
        // A path: an existing folder's gets its "/", to resolve against itself rather than its parent. Asked
        // with links followed (a .checkFileSystem hint does not follow one, so a link to a folder would not).
        let url = URL(filePath: string)
        #if os(Windows)
        // Asked whether it is a folder only when it is a full drive path ("C:\docs", "C:/docs") the content may read:
        // on Windows even testing whether a path exists reaches a share's server with the user's credentials, and a
        // share path, a device path, a relative path and "\name" (both read from a current folder that may be on a
        // share) are not judged as Windows opens them. Such a base is used as written, a folder only when it ends in
        // a separator; the images resolved against it are judged as Windows opens them (readsFileURL) before any
        // is read.
        let head = Array(string.unicodeScalars.prefix(3))
        let drivePath = head.count == 3 && head[0].isASCII && head[0].properties.isAlphabetic && head[1] == ":"
            && (head[2] == "\\" || head[2] == "/")
        guard drivePath, mayProbe(string) else {
            return url
        }
        #endif
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
    /// as `reads` allows (keepingLocalImages), asked about the file: URL's path: resolved first, so a path
    /// that leaves the Markdown's folder is asked about like any other.
    static func document(markdown: String, baseURL: URL?, reads: (String) -> Bool) -> RichTextDocument {
        document(markdown: markdown, baseURL: baseURL, readsURL: { reads($0.path) })
    }

    /// The same, asked about the file: URL itself: on Windows a file: URL with a host names a share, which its
    /// path alone does not show, so the trust policy must see the URL (RenderNode.readsFileURL).
    static func document(markdown: String, baseURL: URL?, readsURL: (URL) -> Bool) -> RichTextDocument {
        let parsed = RichTextDocument(markdown: markdown)
        let resolved = baseURL.map { parsed.resolvingImageURLs(against: $0) } ?? parsed
        return resolved.keepingLocalImages(where: readsURL)
    }
}

extension RichTextDocument {
    /// The document with every file: image whose URL `reads` refuses left without an address. Other
    /// images (web, data, and addresses the package refuses itself) are kept as they are.
    func keepingLocalImages(where reads: (URL) -> Bool) -> RichTextDocument {
        RichTextDocument(blocks: blocks.map { $0.keepingLocalImages(where: reads) })
    }
}

extension RichTextBlock {
    func keepingLocalImages(where reads: (URL) -> Bool) -> RichTextBlock {
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
    func keepingLocalImages(where reads: (URL) -> Bool) -> [RichTextInline] {
        map { $0.keepingLocalImages(where: reads) }
    }
}

extension RichTextInline {
    func keepingLocalImages(where reads: (URL) -> Bool) -> RichTextInline {
        switch self {
        case .image(let alt, let url):
            // A file: URL; the caller judges the file it names (its path, or on Windows the path Windows opens).
            guard let parsed = URL(string: url), parsed.scheme?.lowercased() == "file" else {
                return self
            }
            return reads(parsed) ? self : .image(alt: alt, url: "")
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
