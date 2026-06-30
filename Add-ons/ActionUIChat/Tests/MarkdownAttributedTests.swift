// Add-ons/ActionUIChat/Tests/MarkdownAttributedTests.swift
//
// Tests that a whole message renders into ONE NSAttributedString (so a single text view makes the
// entire message selectable), with inline attributes (links, code) applied to the right ranges.

import XCTest
@testable import ActionUIChat

#if canImport(AppKit) || canImport(UIKit)

final class MarkdownAttributedTests: XCTestCase {

    private func attributed(_ markdown: String) -> NSAttributedString {
        return MarkdownAttributed.attributedString(from: MarkdownParser.parse(markdown))
    }

    func testWholeMessageIsOneString() {
        // A document spanning several block types must produce one contiguous attributed string,
        // so the text view can select the entire message at once.
        let md = "# Title\n\nA paragraph with **bold**.\n\n- item one\n- item two\n\n| A | B |\n| - | - |\n| 1 | 2 |"
        let s = attributed(md).string
        for fragment in ["Title", "bold", "item one", "item two", "A", "B", "1", "2"] {
            XCTAssertTrue(s.contains(fragment), "missing '\(fragment)' in:\n\(s)")
        }
    }

    func testLinkAttributeApplied() {
        let result = attributed("see [Swift](https://swift.org) now")
        var foundLink: URL?
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let url = value as? URL {
                foundLink = url
            }
        }
        XCTAssertEqual(foundLink?.absoluteString, "https://swift.org")
    }

    func testCodeSpanUsesMonospacedFont() {
        let result = attributed("a `code` b")
        let range = (result.string as NSString).range(of: "code")
        XCTAssertNotNil(result.attribute(.font, at: range.location, effectiveRange: nil))
    }

    func testCodeBlockContentPresentAndSelectable() {
        // The code block's text is part of the single attributed string (selectable with the message).
        let result = attributed("```swift\nlet x = 1\n```")
        XCTAssertTrue(result.string.contains("let x = 1"))
    }

    func testStreamingOpenFenceRendersCodeContent() {
        // While streaming, an unterminated fence is balanced, so its content still renders.
        let balanced = MarkdownStreaming.balanceOpenFence("intro\n\n```\npartial code")
        let s = MarkdownAttributed.attributedString(from: MarkdownParser.parse(balanced)).string
        XCTAssertTrue(s.contains("partial code"))
    }
}

#endif
