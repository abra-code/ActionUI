// Tests/Views/TextTests.swift
/*
 TextTests.swift

 Tests for the Text component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        super.tearDown()
    }
    
    func testTextConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "properties": [
                "text": "Hello, World!",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Text.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTextJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Text",
            "properties": {
                "text": "Hello, World!",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Text", "Element type should be Text")
        XCTAssertEqual(element.properties["text"] as? String, "Hello, World!", "text should be Hello, World!")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testTextValidatePropertiesValid() {
        let properties: [String: Any] = [
            "text": "Hello, World!",
            "padding": 10.0
        ]
        
        let validated = Text.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["text"] as? String, "Hello, World!", "text should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testTextValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "text": 123
        ]

        let validated = Text.validateProperties(properties, logger)

        XCTAssertEqual(validated["text"] as? Int, 123, "Invalid text should be preserved for baseline validation")
    }

    func testTextValidatePropertiesMissing() {
        let properties: [String: Any] = [:]

        let validated = Text.validateProperties(properties, logger)

        XCTAssertNil(validated["text"], "Missing text should be nil")
    }

    func testTextValidatePropertiesMarkdownValid() {
        let validated = Text.validateProperties(["markdown": "**bold**"], logger)
        XCTAssertEqual(validated["markdown"] as? String, "**bold**", "Valid markdown should be preserved")
    }

    func testTextValidatePropertiesMarkdownInvalid() {
        let validated = Text.validateProperties(["markdown": 123], logger)
        XCTAssertNil(validated["markdown"], "Non-String markdown should be removed")
    }

    func testTextInitialValueFromMarkdown() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["markdown": "**bold**"]
        let value = Text.initialValue(viewModel) as? String
        XCTAssertEqual(value, "**bold**", "initialValue should return the markdown source")
    }

    func testTextMarkdownTakesPrecedenceOverText() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["text": "plain", "markdown": "**bold**"]
        let value = Text.initialValue(viewModel) as? String
        XCTAssertEqual(value, "**bold**", "markdown should take precedence over text in initialValue")
    }

    func testTextInitialValuePrefersModelValueOverMarkdown() {
        let viewModel = ViewModel()
        viewModel.value = "programmatic"
        viewModel.validatedProperties = ["markdown": "**bold**"]
        let value = Text.initialValue(viewModel) as? String
        XCTAssertEqual(value, "programmatic", "model.value should take precedence over markdown")
    }

    func testTextConstructionWithMarkdown() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "properties": ["markdown": "**Bold** _italic_ `code`"]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Text.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
    }

    // MARK: - setElementValueFromString with contentType

    private func loadTextElement(viewID: Int = 1) throws {
        let elementDict: [String: Any] = [
            "id": viewID,
            "type": "Text",
            "properties": ["text": "initial"]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
    }

    func testSetElementValueFromStringMarkdownContentType() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "**bold**", contentType: "markdown")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "markdown contentType should store AttributedString")
    }

    func testSetElementValueFromStringJSONContentType() throws {
        try loadTextElement()
        let json = "[{\"text\":\"Hello \",\"bold\":true},{\"text\":\"World\"}]"
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: json, contentType: "json")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "json contentType should store AttributedString")
        if let attr = value as? AttributedString {
            XCTAssertEqual(String(attr.characters), "Hello World")
        }
    }

    func testSetElementValueFromStringNilContentTypeFallsThrough() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "plain text")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "plain text", "nil contentType should store plain String")
    }

    func testSetElementValueFromStringPlainContentTypeFallsThrough() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "plain", contentType: "plain")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "plain", "'plain' contentType should store plain String")
    }

    func testSetElementValueFromStringInvalidJSONContentTypeNoOp() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "not json", contentType: "json")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNil(value, "Failed json parse should not update model value")
    }

    // MARK: - getElementValueAsString with contentType

    func testGetElementValueAsStringJSONContentType() throws {
        try loadTextElement()
        var attr = AttributedString("Hello")
        attr.underlineStyle = .single
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: attr)
        let result = ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1, contentType: "json")
        XCTAssertNotNil(result, "json contentType should serialize AttributedString to JSON string")
        guard let result, let data = result.data(using: .utf8) else {
            XCTFail("Result is not valid UTF-8")
            return
        }
        let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(runs, "JSON output should be an array of run dicts")
        let allText = runs?.compactMap { $0["text"] as? String }.joined()
        XCTAssertEqual(allText, "Hello")
    }

    func testGetElementValueAsStringNilContentTypeExtractsPlainText() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: AttributedString("Hello"))
        let result = ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(result, "Hello", "nil contentType on AttributedString should return plain text")
    }

    func testRoundTripMarkdownViaSetAndGetJSON() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "**Bold** World", contentType: "markdown")
        let jsonResult = ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1, contentType: "json")
        XCTAssertNotNil(jsonResult, "Attributed value set via markdown should serialize to JSON")
        if let jsonResult, let data = jsonResult.data(using: .utf8) {
            let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            let allText = runs?.compactMap { $0["text"] as? String }.joined() ?? ""
            XCTAssertTrue(allText.contains("Bold") && allText.contains("World"))
        }
    }

    #if canImport(AppKit) || canImport(UIKit)
    func testSetElementValueFromStringHTMLContentType() throws {
        try loadTextElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "<b>Bold</b>", contentType: "html")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "html contentType should store AttributedString")
        if let attr = value as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Bold"))
        }
    }

    func testSetElementValueFromStringRTFContentType() throws {
        try loadTextElement()
        let rtf = "{\\rtf1\\ansi {\\b Bold}}"
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: rtf, contentType: "rtf")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "rtf contentType should store AttributedString")
        if let attr = value as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Bold"))
        }
    }
    #endif
}
