// Tests/Markdown/MarkdownTextTests.swift
/*
 Tests for markdown as SwiftUI's Text shows it on Linux: the characters and inline styles of the
 AttributedString, against what Apple's AttributedString(markdown:) gives on macOS 27 for the same
 source (measured), and the Pango markup the GtkLabel draws. No display is needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class MarkdownTextTests: XCTestCase {
    private struct Run: Equatable {
        var text: String
        var style: MarkdownStyle = []
        var link: String?
    }

    private func runs(_ markdown: String) -> [Run] {
        let attributed = MarkdownText.attributedString(markdown: markdown)
        return attributed.runs.map { run in
            Run(text: String(attributed[run.range].characters), style: run[MarkdownStyleAttribute.self] ?? [],
                link: run.link?.absoluteString)
        }
    }

    func testBlocksRunTogetherAsInApplesAttributedString() {
        let source = "# Title\nFirst line\nsame paragraph  \nnew line\n\n- one\n- **two**\n\n```\ncode\n```\n---\n> quoted"
        let attributed = MarkdownText.attributedString(markdown: source)
        XCTAssertEqual(String(attributed.characters), "TitleFirst line same paragraph\nnew lineonetwocode\n\u{2E3B}quoted")
    }

    func testInlineStylesAndLinks() {
        XCTAssertEqual(runs("Plain **bold** *italic* ~~gone~~ `code` [link](https://example.com) and snake_case_word"), [
            Run(text: "Plain "), Run(text: "bold", style: .bold), Run(text: " "), Run(text: "italic", style: .italic),
            Run(text: " "), Run(text: "gone", style: .strikethrough), Run(text: " "), Run(text: "code", style: .code),
            Run(text: " "), Run(text: "link", link: "https://example.com"), Run(text: " and snake_case_word"),
        ])
        XCTAssertEqual(runs("***both*** and `**not bold**`"), [
            Run(text: "both", style: [.bold, .italic]), Run(text: " and "), Run(text: "**not bold**", style: .code),
        ])
    }

    func testABareURLLinks() {
        XCTAssertEqual(runs("a < b & \"c\" 'd' https://example.com/x?a=1&b=2."), [
            Run(text: "a < b & \"c\" 'd' "),
            Run(text: "https://example.com/x?a=1&b=2", link: "https://example.com/x?a=1&b=2"),
            Run(text: "."),
        ])
    }

    func testPangoMarkup() {
        XCTAssertNil(MarkdownText.pangoMarkup(MarkdownText.attributedString(markdown: "just text, a < b")),
                     "no styles: the label shows plain text")
        XCTAssertEqual(MarkdownText.pangoMarkup(MarkdownText.attributedString(markdown: "**a** *b* ~~c~~ `d` <e>")),
                       "<b>a</b> <i>b</i> <s>c</s> <tt>d</tt> &lt;e&gt;")
        XCTAssertEqual(MarkdownText.pangoMarkup(MarkdownText.attributedString(markdown: "[go **now**](https://e.com/?a=1&b='2') x")),
                       "<a href=\"https://e.com/?a=1&amp;b=&#39;2&#39;\">go <b>now</b></a> x",
                       "one <a> around the runs of a link, its URL escaped")
    }

    func testEscapingFollowsGMarkup() {
        XCTAssertEqual(MarkdownText.escaped("a&b<c>d\"e'f\u{1}g\u{7F}h\u{85}i\u{9F}j\tk"),
                       "a&amp;b&lt;c&gt;d&quot;e&#39;f&#x1;g&#x7f;h\u{85}i&#x9f;j\tk")
    }
}
