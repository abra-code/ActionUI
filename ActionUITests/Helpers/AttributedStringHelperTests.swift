// Tests/Helpers/AttributedStringHelperTests.swift

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class AttributedStringHelperTests: XCTestCase {
    private var logger: XCTestLogger!

    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - attributedStringParseContent

    func testParseContentMarkdownBold() {
        let result = attributedStringParseContent("**bold**", contentType: "markdown", logger: logger)
        XCTAssertNotNil(result as? AttributedString, "markdown should produce AttributedString")
    }

    func testParseContentMarkdownPlainFallback() {
        let result = attributedStringParseContent("plain text", contentType: "markdown", logger: logger)
        XCTAssertNotNil(result as? AttributedString, "markdown falls back to plain AttributedString on parse failure")
    }

    func testParseContentPlainReturnsNil() {
        let result = attributedStringParseContent("hello", contentType: "plain", logger: logger)
        XCTAssertNil(result, "'plain' should return nil so callers fall through to the String path")
    }

    func testParseContentNilReturnsNil() {
        let result = attributedStringParseContent("hello", contentType: nil, logger: logger)
        XCTAssertNil(result, "nil contentType should return nil")
    }

    func testParseContentUnrecognizedReturnsNil() {
        let result = attributedStringParseContent("hello", contentType: "xml", logger: logger)
        XCTAssertNil(result, "Unrecognized contentType should return nil")
    }

    func testParseContentJSONRuns() {
        let json = "[{\"text\":\"Hello \",\"bold\":true},{\"text\":\"World\"}]"
        let result = attributedStringParseContent(json, contentType: "json", logger: logger)
        XCTAssertNotNil(result as? AttributedString, "Valid JSON runs should produce AttributedString")
        if let attr = result as? AttributedString {
            XCTAssertEqual(String(attr.characters), "Hello World")
        }
    }

    func testParseContentJSONInvalidReturnsNil() {
        let recordingLogger = RecordingLogger()
        let result = attributedStringParseContent("not json", contentType: "json", logger: recordingLogger)
        XCTAssertNil(result, "Invalid JSON should return nil")
        XCTAssertFalse(recordingLogger.warnings.isEmpty, "Invalid JSON should log a warning")
    }

    func testParseContentJSONObjectNotArrayReturnsNil() {
        let recordingLogger = RecordingLogger()
        let result = attributedStringParseContent("{\"key\":\"value\"}", contentType: "json", logger: recordingLogger)
        XCTAssertNil(result, "JSON object (not array of run dicts) should return nil")
    }

    #if canImport(AppKit) || canImport(UIKit)
    func testParseContentHTMLBold() {
        let result = attributedStringParseContent("<b>Hello</b>", contentType: "html", logger: logger)
        XCTAssertNotNil(result as? AttributedString, "Valid HTML should produce AttributedString")
        if let attr = result as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Hello"))
        }
    }

    func testParseContentHTMLWithColor() {
        let html = "<span style=\"color:#CC0000\">Red</span> text"
        let result = attributedStringParseContent(html, contentType: "html", logger: logger)
        XCTAssertNotNil(result as? AttributedString)
        if let attr = result as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Red"))
        }
    }

    func testParseContentRTFBold() {
        let rtf = "{\\rtf1\\ansi {\\b Bold} plain}"
        let result = attributedStringParseContent(rtf, contentType: "rtf", logger: logger)
        XCTAssertNotNil(result as? AttributedString, "Valid RTF should produce AttributedString")
        if let attr = result as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Bold"))
        }
    }

    func testParseContentRTFInvalidReturnsNil() {
        let recordingLogger = RecordingLogger()
        let result = attributedStringParseContent("not valid rtf content", contentType: "rtf", logger: recordingLogger)
        XCTAssertNil(result, "Non-RTF string should return nil")
        XCTAssertFalse(recordingLogger.warnings.isEmpty, "Invalid RTF should log a warning")
    }
    #endif

    // MARK: - attributedStringSerializeContent

    func testSerializeNonAttributedStringReturnsNil() {
        let result = attributedStringSerializeContent("plain string", contentType: "json", logger: logger)
        XCTAssertNil(result, "Non-AttributedString value should return nil")
    }

    func testSerializePlainContentType() {
        let attr = AttributedString("Hello World")
        let result = attributedStringSerializeContent(attr, contentType: "plain", logger: logger)
        XCTAssertEqual(result, "Hello World")
    }

    func testSerializeNilContentTypeExtractsPlainText() {
        let attr = AttributedString("Hello")
        let result = attributedStringSerializeContent(attr, contentType: nil, logger: logger)
        XCTAssertEqual(result, "Hello")
    }

    func testSerializeJSONContentTypeProducesArray() {
        let attr = AttributedString("Hello")
        let result = attributedStringSerializeContent(attr, contentType: "json", logger: logger)
        XCTAssertNotNil(result, "json contentType should produce a JSON string")
        guard let result, let data = result.data(using: .utf8) else {
            XCTFail("Result is not valid UTF-8")
            return
        }
        let parsed = try? JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(parsed as? [[String: Any]], "Serialized JSON should be an array of run dicts")
    }

    // MARK: - attributedStringFromJSONRuns

    func testFromJSONRunsTextOnly() {
        let runs: [[String: Any]] = [["text": "Hello"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(String(result.characters), "Hello")
    }

    func testFromJSONRunsMultipleRuns() {
        let runs: [[String: Any]] = [["text": "Hello "], ["text": "World"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(String(result.characters), "Hello World")
    }

    func testFromJSONRunsBoldAppliesFont() {
        let runs: [[String: Any]] = [["text": "bold", "bold": true]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertNotNil(result.runs.first?.font, "bold run should set a font")
    }

    func testFromJSONRunsItalicAppliesFont() {
        let runs: [[String: Any]] = [["text": "italic", "italic": true]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertNotNil(result.runs.first?.font, "italic run should set a font")
    }

    func testFromJSONRunsUnderline() {
        let runs: [[String: Any]] = [["text": "underlined", "underline": true]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(result.runs.first?.underlineStyle, .single)
    }

    func testFromJSONRunsStrikethrough() {
        let runs: [[String: Any]] = [["text": "struck", "strikethrough": true]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(result.runs.first?.strikethroughStyle, .single)
    }

    func testFromJSONRunsColor() {
        let runs: [[String: Any]] = [["text": "red", "color": "#FF0000"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertNotNil(result.runs.first?.foregroundColor, "color run should set foregroundColor")
    }

    func testFromJSONRunsBackgroundColor() {
        let runs: [[String: Any]] = [["text": "bg", "backgroundColor": "#FFFF00"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertNotNil(result.runs.first?.backgroundColor, "backgroundColor run should set backgroundColor")
    }

    func testFromJSONRunsLink() {
        let runs: [[String: Any]] = [["text": "link", "link": "https://example.com"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(result.runs.first?.link?.absoluteString, "https://example.com")
    }

    func testFromJSONRunsInvalidLinkIgnored() {
        let runs: [[String: Any]] = [["text": "bad", "link": "not a url ⚠️"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(String(result.characters), "bad", "Run with invalid URL should still produce text")
    }

    func testFromJSONRunsFontSize() {
        let runs: [[String: Any]] = [["text": "big", "fontSize": 24.0]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertNotNil(result.runs.first?.font, "fontSize run should set font")
    }

    func testFromJSONRunsKern() {
        let runs: [[String: Any]] = [["text": "spaced", "kern": 2.5]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(result.runs.first?.kern, 2.5)
    }

    func testFromJSONRunsBaselineOffset() {
        let runs: [[String: Any]] = [["text": "sup", "baselineOffset": 4.0]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(result.runs.first?.baselineOffset, 4.0)
    }

    func testFromJSONRunsSkipsRunWithoutTextKey() {
        let runs: [[String: Any]] = [["bold": true], ["text": "only"]]
        let result = attributedStringFromJSONRuns(runs)
        XCTAssertEqual(String(result.characters), "only", "Run without 'text' key should be skipped")
    }

    func testFromJSONRunsEmpty() {
        let result = attributedStringFromJSONRuns([])
        XCTAssertEqual(String(result.characters), "")
    }

    // MARK: - attributedStringToJSONRuns

    func testToJSONRunsPlainText() throws {
        let attr = AttributedString("Hello")
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0]["text"] as? String, "Hello")
    }

    func testToJSONRunsUnderline() throws {
        var attr = AttributedString("underlined")
        attr.underlineStyle = .single
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.first?["underline"] as? Bool, true)
    }

    func testToJSONRunsStrikethrough() throws {
        var attr = AttributedString("struck")
        attr.strikethroughStyle = .single
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.first?["strikethrough"] as? Bool, true)
    }

    func testToJSONRunsLink() throws {
        var attr = AttributedString("link")
        attr.link = URL(string: "https://example.com")
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.first?["link"] as? String, "https://example.com")
    }

    func testToJSONRunsZeroKernOmitted() throws {
        var attr = AttributedString("text")
        attr.kern = 0
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNil(runs.first?["kern"], "Zero kern should be omitted from serialized output")
    }

    func testToJSONRunsZeroBaselineOffsetOmitted() throws {
        var attr = AttributedString("text")
        attr.baselineOffset = 0
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNil(runs.first?["baselineOffset"], "Zero baselineOffset should be omitted")
    }

    // MARK: - Round-trip

    func testRoundTripUnderlineAndStrikethrough() throws {
        let originalRuns: [[String: Any]] = [
            ["text": "Hello ", "underline": true],
            ["text": "World", "strikethrough": true]
        ]
        let attr = attributedStringFromJSONRuns(originalRuns)
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let recovered = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(recovered.count, 2)
        XCTAssertEqual(recovered[0]["text"] as? String, "Hello ")
        XCTAssertEqual(recovered[0]["underline"] as? Bool, true)
        XCTAssertEqual(recovered[1]["text"] as? String, "World")
        XCTAssertEqual(recovered[1]["strikethrough"] as? Bool, true)
    }

    func testRoundTripLink() throws {
        let originalRuns: [[String: Any]] = [["text": "click", "link": "https://example.com"]]
        let attr = attributedStringFromJSONRuns(originalRuns)
        let json = try XCTUnwrap(attributedStringToJSONRuns(attr))
        let data = try XCTUnwrap(json.data(using: .utf8))
        let recovered = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(recovered.first?["link"] as? String, "https://example.com")
    }

    func testRoundTripViaParseAndSerialize() throws {
        let jsonInput = "[{\"text\":\"Hello\",\"underline\":true},{\"text\":\" World\",\"strikethrough\":true}]"
        let attr = try XCTUnwrap(attributedStringParseContent(jsonInput, contentType: "json", logger: logger) as? AttributedString)
        let serialized = try XCTUnwrap(attributedStringSerializeContent(attr, contentType: "json", logger: logger))
        let data = try XCTUnwrap(serialized.data(using: .utf8))
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let allText = runs.compactMap { $0["text"] as? String }.joined()
        XCTAssertEqual(allText, "Hello World")
    }
}

// MARK: - RecordingLogger (reuse pattern from ActionUIModelTests)

private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var warnings: [String] = []
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        switch level {
        case .warning: warnings.append(message)
        case .error:   errors.append(message)
        default:       break
        }
    }
}
