// Add-ons/ActionUIRichText/Tests/RichTextElementTests.swift
//
// Element-level tests of the ActionUIRichText add-on: how the "remoteImages" property turns into the
// view's remote-image policy. Reaches internals via @testable import.

import XCTest
@testable import ActionUIRichText
import RichText

@MainActor
final class RichTextRemoteImagesTests: XCTestCase {

    func testTheThreeNamesGiveTheirPolicy() {
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("automatic"), .automatic)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("on-click"), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("never"), .never)
    }

    func testAbsentIsAutomatic() {
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(nil), .automatic)
    }

    func testAnyOtherValueFailsClosedToOnClick() {
        // A misspelling, another case, or another type: whoever set the key meant to restrict fetching.
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("onclick"), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy("Never"), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(""), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(false), .onClick)
        XCTAssertEqual(RichTextView.effectiveRemoteImagesPolicy(0), .onClick)
    }
}

/// Local (file:) images in the Markdown: each is asked about by its path, and a refused one keeps its alt
/// text but loses its address; other images pass as they are.
@MainActor
final class RichTextLocalImagesTests: XCTestCase {

    func testARefusedLocalImageLosesItsAddressOnly() {
        let markdown = """
        # ![a](file:///etc/hosts) heading

        ![b](https://example.com/b.png) ![c](data:image/png;base64,AA==) *![d](FILE:///tmp/x%20y.png)*

        > - [![e](file:///allowed/e.png)](https://example.com)

        | ![f](file:///etc/f.png) |
        |---|
        | ![g](file:///allowed/g.png) |
        """
        var asked: [String] = []
        let document = RichTextDocument(markdown: markdown).keepingLocalImages { url in
            asked.append(url.path)
            return url.path.hasPrefix("/allowed/")
        }
        XCTAssertEqual(asked, ["/etc/hosts", "/tmp/x y.png", "/allowed/e.png", "/etc/f.png", "/allowed/g.png"])
        let images = document.blocks.flatMap(Self.images)
        XCTAssertEqual(images.map(\.alt), ["a", "b", "c", "d", "e", "f", "g"], "every image keeps its alt text")
        XCTAssertEqual(images.map(\.url), ["", "https://example.com/b.png", "data:image/png;base64,AA==", "",
                                           "file:///allowed/e.png", "", "file:///allowed/g.png"])
    }

    func testMarkdownWithNoLocalImagesIsUnchanged() {
        let document = RichTextDocument(markdown: "Text, `code`, [a link](https://example.com) and ![x](https://example.com/x.png).")
        XCTAssertEqual(document.keepingLocalImages { _ in false }, document)
    }

    func testRelativeImagePathsResolveAgainstTheMarkdownsLocation() {
        let markdown = "![same](logo.png) ![sub](img/a.png) ![up](../../logo.png) ![web](https://example.com/w.png)"
        var asked: [String] = []
        let document = RichTextView.document(markdown: markdown, baseURL: URL(fileURLWithPath: "/docs/guide/deep/README.md")) { path in
            asked.append(path)
            return path != "/docs/logo.png"
        }
        // Resolved first, so the path that leaves the Markdown's folder is asked about like the others.
        XCTAssertEqual(asked, ["/docs/guide/deep/logo.png", "/docs/guide/deep/img/a.png", "/docs/logo.png"])
        XCTAssertEqual(document.blocks.flatMap(Self.images).map(\.url),
                       ["file:///docs/guide/deep/logo.png", "file:///docs/guide/deep/img/a.png", "", "https://example.com/w.png"])
    }

    func testWithoutABaseARelativeImagePathStaysRelative() {
        var asked: [String] = []
        let document = RichTextView.document(markdown: "![same](logo.png)", baseURL: nil) { asked.append($0); return true }
        XCTAssertEqual(asked, [], "nothing local to ask about: the package cannot load it")
        XCTAssertEqual(document.blocks.flatMap(Self.images).map(\.url), ["logo.png"])
    }

    func testTheBaseURLProperty() throws {
        XCTAssertNil(RichTextView.markdownBaseURL(nil))
        XCTAssertNil(RichTextView.markdownBaseURL(""))
        XCTAssertNil(RichTextView.markdownBaseURL(5))
        XCTAssertNil(RichTextView.markdownBaseURL("javascript:alert(1)"), "only file:, http: and https: addresses")
        XCTAssertEqual(RichTextView.markdownBaseURL("https://example.com/docs/")?.absoluteString, "https://example.com/docs/")
        XCTAssertEqual(RichTextView.markdownBaseURL("file:///docs/README.md")?.path, "/docs/README.md")
        XCTAssertEqual(RichTextView.markdownBaseURL("/no/such/folder/README.md")?.absoluteString, "file:///no/such/folder/README.md")
        // An existing folder's path resolves against the folder itself, with or without its "/".
        let folder = FileManager.default.temporaryDirectory.path
        let trimmed = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        let base = try XCTUnwrap(RichTextView.markdownBaseURL(trimmed))
        XCTAssertEqual(URL(string: "logo.png", relativeTo: base)?.path, trimmed + "/logo.png")
        // And so does a symbolic link to a folder.
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("RichTextBaseURL-\(UUID().uuidString)").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: trimmed)
        defer { try? FileManager.default.removeItem(atPath: link) }
        let linked = try XCTUnwrap(RichTextView.markdownBaseURL(link))
        XCTAssertEqual(URL(string: "logo.png", relativeTo: linked)?.path, link + "/logo.png")
    }

    private static func images(_ block: RichTextBlock) -> [(alt: String, url: String)] {
        switch block {
        case .heading(_, let inlines), .paragraph(let inlines):
            return inlines.flatMap(images)
        case .blockQuote(let blocks):
            return blocks.flatMap(images)
        case .list(_, _, _, let items):
            return items.flatMap { $0.flatMap(images) }
        case .table(let headers, _, let rows):
            return headers.flatMap { $0.flatMap(images) } + rows.flatMap { $0.flatMap { $0.flatMap(images) } }
        case .codeBlock, .thematicBreak:
            return []
        }
    }

    private static func images(_ inline: RichTextInline) -> [(alt: String, url: String)] {
        switch inline {
        case .image(let alt, let url):
            return [(alt, url)]
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return children.flatMap(images)
        case .link(let text, _):
            return text.flatMap(images)
        case .text, .code, .lineBreak:
            return []
        }
    }
}
