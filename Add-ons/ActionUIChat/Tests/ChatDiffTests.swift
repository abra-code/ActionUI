// Add-ons/ActionUIChat/Tests/ChatDiffTests.swift
//
// Tests for the standalone diff-viewer component (Sources/Diff/): the line-diff
// model (DiffComputer - interleaving, line numbers, context collapsing, degenerate
// cases) and DiffView's rendering-cap arithmetic. Deliberately free of Chat types,
// matching the component's extraction story.

import XCTest
@testable import ActionUIChat

final class DiffComputerTests: XCTestCase {

    private func kinds(_ result: DiffResult) -> [DiffLine.Kind] {
        result.hunks.flatMap(\.lines).map(\.kind)
    }

    func testIdenticalTexts() {
        let result = DiffComputer.compute(oldText: "a\nb\n", newText: "a\nb\n")
        XCTAssertTrue(result.isIdentical)
        XCTAssertTrue(result.hunks.isEmpty)
        XCTAssertEqual(result.trailingSkippedLines, 2)
    }

    func testPureAdditionFromEmpty() {
        // An empty old text is ZERO lines, so a new file diffs as pure additions.
        let result = DiffComputer.compute(oldText: "", newText: "one\ntwo\n")
        XCTAssertEqual(kinds(result), [.added, .added])
        XCTAssertEqual(result.hunks[0].lines.map(\.newNumber), [1, 2])
        XCTAssertEqual(result.hunks[0].lines.map(\.oldNumber), [nil, nil])
    }

    func testPureRemoval() {
        let result = DiffComputer.compute(oldText: "one\ntwo\n", newText: "")
        XCTAssertEqual(kinds(result), [.removed, .removed])
        XCTAssertEqual(result.hunks[0].lines.map(\.oldNumber), [1, 2])
    }

    func testChangedLineEmitsRemovalBeforeAddition() {
        let result = DiffComputer.compute(oldText: "keep\nold\nkeep2\n", newText: "keep\nnew\nkeep2\n")
        XCTAssertEqual(kinds(result), [.context, .removed, .added, .context],
                       "unified-diff convention: minus before plus at a change point")
        let lines = result.hunks[0].lines
        XCTAssertEqual(lines[1].text, "old")
        XCTAssertEqual(lines[1].oldNumber, 2)
        XCTAssertNil(lines[1].newNumber)
        XCTAssertEqual(lines[2].text, "new")
        XCTAssertEqual(lines[2].newNumber, 2)
        XCTAssertNil(lines[2].oldNumber)
    }

    func testContextNumbersTrackBothSides() {
        let result = DiffComputer.compute(oldText: "a\nx\nb\n", newText: "a\nb\n")
        // a (1/1), -x (2/-), b (3/2)
        let lines = result.hunks[0].lines
        XCTAssertEqual(lines.map(\.kind), [.context, .removed, .context])
        XCTAssertEqual(lines[2].oldNumber, 3)
        XCTAssertEqual(lines[2].newNumber, 2)
    }

    func testLongUnchangedRunsCollapseIntoHunks() {
        let filler = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let oldText = "START\n" + filler + "\nEND\n"
        let newText = "CHANGED\n" + filler + "\nEND2\n"
        let result = DiffComputer.compute(oldText: oldText, newText: newText, context: 2)

        XCTAssertEqual(result.hunks.count, 2, "two distant changes must become two hunks")
        XCTAssertEqual(result.hunks[0].skippedBefore, 0)
        // Hunk 1: -START +CHANGED + 2 context; hunk 2: 2 context -END +END2.
        // 20 filler lines minus 2 context on each side leaves 16 collapsed.
        XCTAssertEqual(result.hunks[1].skippedBefore, 16)
        XCTAssertEqual(result.trailingSkippedLines, 0)
    }

    func testTrailingUnchangedRunIsCounted() {
        let filler = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let result = DiffComputer.compute(oldText: "old\n" + filler, newText: "new\n" + filler, context: 1)
        XCTAssertEqual(result.hunks.count, 1)
        XCTAssertEqual(result.trailingSkippedLines, 9, "10 filler lines minus 1 context line")
    }

    func testTrailingNewlineIsATerminatorNotALine() {
        let result = DiffComputer.compute(oldText: "a", newText: "a\n")
        XCTAssertTrue(result.isIdentical, "'a' and 'a\\n' are the same single line")
    }

    func testSizeLimit() {
        let big = (1...30).map(String.init).joined(separator: "\n")
        let result = DiffComputer.compute(oldText: big, newText: big + "\nx", sizeLimit: 50)
        XCTAssertTrue(result.exceedsSizeLimit)
        XCTAssertTrue(result.hunks.isEmpty)
    }
}

final class DiffViewTruncationTests: XCTestCase {

    private func makeResult(hunkSizes: [Int]) -> DiffResult {
        var hunks: [DiffHunk] = []
        var ordinal = 0
        for (index, size) in hunkSizes.enumerated() {
            let lines = (0..<size).map { _ -> DiffLine in
                let line = DiffLine(id: ordinal, kind: .added, text: "x", oldNumber: nil, newNumber: ordinal + 1)
                ordinal += 1
                return line
            }
            hunks.append(DiffHunk(id: index, lines: lines, skippedBefore: 0))
        }
        return DiffResult(hunks: hunks, trailingSkippedLines: 0, isIdentical: false, exceedsSizeLimit: false)
    }

    func testEverythingFitsUnderTheLimit() {
        let visible = DiffView.visibleLines(of: makeResult(hunkSizes: [4, 6]), limit: 10)
        XCTAssertEqual(visible.hunkCount, 2)
        XCTAssertEqual(visible.linesInLastHunk, 6)
        XCTAssertEqual(visible.truncatedLineCount, 0)
    }

    func testTruncationCutsInsideAHunk() {
        let visible = DiffView.visibleLines(of: makeResult(hunkSizes: [4, 6, 5]), limit: 7)
        XCTAssertEqual(visible.hunkCount, 2, "the second hunk is the last visible one")
        XCTAssertEqual(visible.linesInLastHunk, 3, "4 whole + 3 of the second = 7")
        XCTAssertEqual(visible.truncatedLineCount, 8, "15 total - 7 rendered")
    }
}
