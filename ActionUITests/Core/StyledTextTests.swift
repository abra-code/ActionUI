// Core/StyledTextTests.swift
/*
 Tests for StyledText, the JSON runs format of Text and TextEditor: parsing the runs (keys, flags,
 numbers, runs without text, text that is not runs) and writing them back.
 (The AttributedString conversion is tested in AttributedStringHelperTests.)
*/

import XCTest
@testable import ActionUI

final class StyledTextTests: XCTestCase {

    func testParseReadsEveryKey() throws {
        let styled = try XCTUnwrap(StyledText.parse(jsonRuns: """
        [{"text":"Hi","bold":true,"italic":true,"underline":true,"strikethrough":true,
          "color":"#FF0000","backgroundColor":"blue","link":"https://example.com/a",
          "kern":1.5,"baselineOffset":-2,"fontSize":16}]
        """))
        XCTAssertEqual(styled.runs, [StyledRun(
            text: "Hi", bold: true, italic: true, underline: true, strikethrough: true,
            color: "#FF0000", backgroundColor: "blue", link: "https://example.com/a",
            kern: 1.5, baselineOffset: -2, fontSize: 16)])
    }

    func testFlagsAreTrueOrOneAndNumbersAreJSONNumbers() throws {
        let styled = try XCTUnwrap(StyledText.parse(jsonRuns: """
        [{"text":"a","bold":1,"italic":1.0,"underline":0,"strikethrough":"true","kern":"2","fontSize":true},
         {"text":"b","bold":false,"italic":2}]
        """))
        XCTAssertEqual(styled.runs[0], StyledRun(text: "a", bold: true, italic: true))
        XCTAssertEqual(styled.runs[1], StyledRun(text: "b"))
    }

    func testARunWithoutTextIsSkipped() throws {
        let styled = try XCTUnwrap(StyledText.parse(jsonRuns: #"[{"bold":true},{"text":5},{"text":""},{"text":"x"}]"#))
        XCTAssertEqual(styled.runs.map(\.text), ["", "x"])
    }

    func testTextThatIsNotRunsIsNil() {
        for text in ["", "not json", "{\"text\":\"a\"}", "[1, 2]", "[{\"text\":\"a\"}, 3]", "\"a\"", "null"] {
            XCTAssertNil(StyledText.parse(jsonRuns: text), text)
        }
        XCTAssertEqual(StyledText.parse(jsonRuns: "[]"), StyledText(runs: []))
    }

    func testJSONStringWritesSetKeysSortedAndOmitsZeroKernAndBaseline() {
        var run = StyledRun(text: "Go/now")
        run.underline = true
        run.color = "#00FF00"
        run.link = "https://example.com/x"
        run.kern = 0
        run.baselineOffset = 2.5
        XCTAssertEqual(StyledText(runs: [run, StyledRun(text: "")]).jsonString(),
                       ##"[{"baselineOffset":2.5,"color":"#00FF00","link":"https:\/\/example.com\/x","text":"Go\/now","underline":true},{"text":""}]"##)
        XCTAssertEqual(StyledText(runs: []).jsonString(), "[]")
    }

    func testRoundTrip() throws {
        let runs = [
            StyledRun(text: "One", bold: true, strikethrough: true, color: "red", kern: 1.25),
            StyledRun(text: "Two", italic: true, link: "https://a.b/c", baselineOffset: -1, fontSize: 12),
        ]
        let text = try XCTUnwrap(StyledText(runs: runs).jsonString())
        XCTAssertEqual(StyledText.parse(jsonRuns: text)?.runs, runs)
    }
}
