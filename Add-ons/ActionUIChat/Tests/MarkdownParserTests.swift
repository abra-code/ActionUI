// Add-ons/ActionUIChat/Tests/MarkdownParserTests.swift
//
// Unit tests for the dependency-free Markdown engine (M2): the block + inline parser, the
// streaming open-fence balancer, and the local transport's reply chunker. These exercise the
// parse logic directly (the SwiftUI rendering is verified visually in the demo apps).

import XCTest
@testable import ActionUIChat

final class MarkdownParserTests: XCTestCase {

    // MARK: Inline

    func testPlainParagraph() {
        XCTAssertEqual(MarkdownParser.parse("hello world"),
                       [.paragraph([.text("hello world")])])
    }

    func testEmphasisAndStrong() {
        XCTAssertEqual(MarkdownParser.parse("*a* **b** ***c***"),
                       [.paragraph([
                            .emphasis([.text("a")]),
                            .text(" "),
                            .strong([.text("b")]),
                            .text(" "),
                            .strong([.emphasis([.text("c")])]),
                       ])])
    }

    func testInlineCodeAndStrike() {
        XCTAssertEqual(MarkdownParser.parse("`x` ~~y~~"),
                       [.paragraph([.code("x"), .text(" "), .strikethrough([.text("y")])])])
    }

    func testLink() {
        XCTAssertEqual(MarkdownParser.parse("see [Swift](https://swift.org)"),
                       [.paragraph([
                            .text("see "),
                            .link(text: [.text("Swift")], url: "https://swift.org"),
                       ])])
    }

    func testEscape() {
        XCTAssertEqual(MarkdownParser.parse("a \\*b\\* c"),
                       [.paragraph([.text("a *b* c")])])
    }

    // Streaming safety: an unterminated span must render as literal text, never swallow the rest.
    func testUnterminatedEmphasisIsLiteral() {
        XCTAssertEqual(MarkdownParser.parse("a **bold and more"),
                       [.paragraph([.text("a **bold and more")])])
    }

    func testUnterminatedCodeSpanIsLiteral() {
        XCTAssertEqual(MarkdownParser.parse("a `code"),
                       [.paragraph([.text("a `code")])])
    }

    // MARK: Blocks

    func testHeadings() {
        XCTAssertEqual(MarkdownParser.parse("# One"), [.heading(level: 1, [.text("One")])])
        XCTAssertEqual(MarkdownParser.parse("### Three"), [.heading(level: 3, [.text("Three")])])
    }

    func testFencedCode() {
        let md = "```swift\nlet x = 1\nprint(x)\n```"
        XCTAssertEqual(MarkdownParser.parse(md),
                       [.codeBlock(language: "swift", code: "let x = 1\nprint(x)")])
    }

    func testThematicBreak() {
        XCTAssertEqual(MarkdownParser.parse("---"), [.thematicBreak])
        XCTAssertEqual(MarkdownParser.parse("***"), [.thematicBreak])
    }

    func testUnorderedList() {
        let result = MarkdownParser.parse("- one\n- two")
        XCTAssertEqual(result, [.list(ordered: false, start: 1, tight: true, items: [
            [.paragraph([.text("one")])],
            [.paragraph([.text("two")])],
        ])])
    }

    func testOrderedListStart() {
        let result = MarkdownParser.parse("3. a\n4. b")
        guard case .list(let ordered, let start, _, let items) = result.first else {
            return XCTFail("expected a list, got \(result)")
        }
        XCTAssertTrue(ordered)
        XCTAssertEqual(start, 3)
        XCTAssertEqual(items.count, 2)
    }

    func testNestedList() {
        let md = "- outer\n  - inner a\n  - inner b"
        guard case .list(_, _, _, let items) = MarkdownParser.parse(md).first, let first = items.first else {
            return XCTFail("expected a list")
        }
        // The item holds a paragraph ("outer") and a nested list with two items.
        let nested = first.compactMap { block -> [[MarkdownBlock]]? in
            if case .list(_, _, _, let inner) = block {
                return inner
            }
            return nil
        }
        XCTAssertEqual(nested.first?.count, 2, "outer item should contain a 2-item nested list")
    }

    func testBlockQuote() {
        XCTAssertEqual(MarkdownParser.parse("> quoted"),
                       [.blockQuote([.paragraph([.text("quoted")])])])
    }

    func testTable() {
        let md = "| A | B |\n| --- | :--: |\n| 1 | 2 |"
        guard case .table(let headers, let aligns, let rows) = MarkdownParser.parse(md).first else {
            return XCTFail("expected a table")
        }
        XCTAssertEqual(headers, [[.text("A")], [.text("B")]])
        XCTAssertEqual(aligns, [.none, .center])
        XCTAssertEqual(rows, [[[.text("1")], [.text("2")]]])
    }

    func testMixedDocumentBlockCount() {
        let md = "# Title\n\npara\n\n- a\n- b\n\n```\ncode\n```"
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 4)
    }

    // MARK: Streaming helpers

    func testBalanceOpenFenceAppendsClose() {
        let open = "intro\n\n```swift\nlet x = 1"
        let balanced = MarkdownStreaming.balanceOpenFence(open)
        XCTAssertTrue(balanced.hasSuffix("\n```"))
        // After balancing, the open fence parses as a code block (not swallowed text).
        let blocks = MarkdownParser.parse(balanced)
        XCTAssertTrue(blocks.contains { if case .codeBlock = $0 { return true }; return false })
    }

    func testBalanceOpenFenceNoopWhenClosed() {
        let closed = "```\nlet x = 1\n```"
        XCTAssertEqual(MarkdownStreaming.balanceOpenFence(closed), closed)
    }

    // MARK: Transport reply chunking

    func testStreamingChunksReassembleExactly() {
        let source = ChatReplyContent.make(style: "markdown", prompt: "hi there")
        let chunks = ChatReplyContent.streamingChunks(source)
        XCTAssertTrue(chunks.count > 1)
        XCTAssertEqual(chunks.joined(), source, "streaming chunks must reproduce the source exactly")
    }

    func testEchoReplyIsPlain() {
        XCTAssertEqual(ChatReplyContent.make(style: "echo", prompt: "ping"), "You said: ping")
    }

    // The markdown showcase reply must itself be valid, multi-block Markdown.
    func testMarkdownShowcaseParses() {
        let source = ChatReplyContent.make(style: "markdown", prompt: "demo")
        let blocks = MarkdownParser.parse(source)
        XCTAssertTrue(blocks.contains { if case .heading = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .codeBlock = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .table = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .list = $0 { return true }; return false })
    }
}
