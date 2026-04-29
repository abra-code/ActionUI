// Tests/Views/TextEditorTests.swift
/*
 TextEditorTests.swift

 Tests for the TextEditor component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextEditorTests: XCTestCase {
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
    
    func testTextEditorValidatePropertiesValid() {
        let properties: [String: Any] = [
            "placeholder": "Enter text here",
            "actionID": "texteditor.submit"
        ]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Enter text here", "Placeholder should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "texteditor.submit", "actionID should be valid")
    }
    
    func testTextEditorValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "placeholder": 123
        ]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Invalid placeholder should be nil")
    }
    
    func testTextEditorValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Missing placeholder should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    func testTextEditorConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextEditor",
            "properties": [
                "placeholder": "Enter text here",
                "actionID": "texteditor.submit",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = TextEditor.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTextEditorJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TextEditor",
            "properties": {
                "placeholder": "Enter text here",
                "actionID": "texteditor.submit",
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
        XCTAssertEqual(element.type, "TextEditor", "Element type should be TextEditor")
        XCTAssertEqual(element.properties["placeholder"] as? String, "Enter text here", "placeholder should be Enter text here")
        XCTAssertEqual(element.properties["actionID"] as? String, "texteditor.submit", "actionID should be texteditor.submit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? String, "", "Initial viewModel value should be an empty string")
    }

    func testTextEditorTextPropertyValidation() {
        let valid = TextEditor.validateProperties(["text": "hello"], logger)
        XCTAssertEqual(valid["text"] as? String, "hello", "Valid text should be preserved")

        let invalid = TextEditor.validateProperties(["text": 123], logger)
        XCTAssertNil(invalid["text"], "Non-String text should be removed")
    }

    func testTextEditorInitialValueFromTextProperty() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["text": "initial content"]

        let value = TextEditor.initialValue(viewModel) as? String
        XCTAssertEqual(value, "initial content", "initialValue should fall back to text property")
    }

    func testTextEditorInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = "edited"
        viewModel.validatedProperties = ["text": "initial content"]

        let value = TextEditor.initialValue(viewModel) as? String
        XCTAssertEqual(value, "edited", "initialValue should prefer model.value over text property")
    }

    func testTextEditorValidatePropertiesMarkdownValid() {
        let validated = TextEditor.validateProperties(["markdown": "**bold** _italic_"], logger)
        XCTAssertEqual(validated["markdown"] as? String, "**bold** _italic_", "Valid markdown should be preserved")
    }

    func testTextEditorValidatePropertiesMarkdownInvalid() {
        let validated = TextEditor.validateProperties(["markdown": 123], logger)
        XCTAssertNil(validated["markdown"], "Non-String markdown should be removed")
    }

    func testTextEditorValidatePropertiesBothTextAndMarkdown() {
        let validated = TextEditor.validateProperties(["text": "plain", "markdown": "**bold**"], logger)
        XCTAssertEqual(validated["text"] as? String, "plain", "text should be preserved when both properties are provided")
        XCTAssertEqual(validated["markdown"] as? String, "**bold**", "markdown should be preserved when both properties are provided")
    }

    func testTextEditorInitialValueFromAttributedMarkdown() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["markdown": "**bold** _italic_"]
        let value = TextEditor.initialValue(viewModel) as? String
        XCTAssertEqual(value, "**bold** _italic_", "initialValue should fall back to markdown source")
    }

    func testTextEditorInitialValuePrefersTextOverMarkdown() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["text": "plain", "markdown": "**bold**"]
        let value = TextEditor.initialValue(viewModel) as? String
        XCTAssertEqual(value, "plain", "text property should take precedence over markdown in plain-text fallback path")
    }

    func testTextEditorInitialValueFromAttributedStringModelValue() {
        let viewModel = ViewModel()
        viewModel.value = AttributedString("some content")
        let value = TextEditor.initialValue(viewModel) as? String
        XCTAssertEqual(value, "some content", "initialValue should extract plain text from an AttributedString model value")
    }

    func testTextEditorInitialValuePrefersStringModelValueOverMarkdown() {
        let viewModel = ViewModel()
        viewModel.value = "edited"
        viewModel.validatedProperties = ["markdown": "**bold**"]
        let value = TextEditor.initialValue(viewModel) as? String
        XCTAssertEqual(value, "edited", "String model.value should take precedence over markdown property")
    }

    func testTextEditorConstructionWithMarkdown() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextEditor",
            "properties": [
                "markdown": "**Bold** _italic_ initial content",
                "placeholder": "Edit attributed text"
            ]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = TextEditor.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
    }

    // MARK: - setElementValueFromString with contentType

    private func loadTextEditorElement(viewID: Int = 1) throws {
        let elementDict: [String: Any] = [
            "id": viewID,
            "type": "TextEditor",
            "properties": ["text": "initial"]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
    }

    func testSetElementValueFromStringMarkdownContentType() throws {
        try loadTextEditorElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "**bold** _italic_", contentType: "markdown")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "markdown contentType should store AttributedString in TextEditor")
    }

    func testSetElementValueFromStringJSONContentType() throws {
        try loadTextEditorElement()
        let json = "[{\"text\":\"Hello \",\"bold\":true},{\"text\":\"World\",\"italic\":true}]"
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: json, contentType: "json")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "json contentType should store AttributedString in TextEditor")
        if let attr = value as? AttributedString {
            XCTAssertEqual(String(attr.characters), "Hello World")
        }
    }

    func testSetElementValueFromStringNilContentTypeFallsThrough() throws {
        try loadTextEditorElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "plain text")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "plain text", "nil contentType should store plain String in TextEditor")
    }

    func testSetElementValueFromStringPlainContentTypeFallsThrough() throws {
        try loadTextEditorElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "plain", contentType: "plain")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "plain", "'plain' contentType should store plain String in TextEditor")
    }

    func testSetElementValueFromStringInvalidJSONContentTypeFallsThrough() throws {
        try loadTextEditorElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "not json", contentType: "json")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "not json", "Invalid JSON parse should fall back to plain string")
    }

    // MARK: - getElementValueAsString with contentType

    func testGetElementValueAsStringJSONContentType() throws {
        try loadTextEditorElement()
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
        try loadTextEditorElement()
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: AttributedString("Hello"))
        let result = ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(result, "Hello", "nil contentType on AttributedString should return plain text")
    }

    func testRoundTripJSONContentType() throws {
        try loadTextEditorElement()
        let json = "[{\"text\":\"Hello \",\"underline\":true},{\"text\":\"World\",\"strikethrough\":true}]"
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: json, contentType: "json")
        let serialized = ActionUIModel.shared.getElementValueAsString(windowUUID: windowUUID, viewID: 1, contentType: "json")
        XCTAssertNotNil(serialized, "Round-trip: getElementValueAsString(json) should return JSON")
        if let serialized, let data = serialized.data(using: .utf8) {
            let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            let allText = runs?.compactMap { $0["text"] as? String }.joined() ?? ""
            XCTAssertEqual(allText, "Hello World")
        }
    }

    #if canImport(AppKit) || canImport(UIKit)
    func testSetElementValueFromStringHTMLContentType() throws {
        try loadTextEditorElement()
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "<b>Bold</b> text", contentType: "html")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "html contentType should store AttributedString in TextEditor")
        if let attr = value as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Bold"))
        }
    }

    func testSetElementValueFromStringRTFContentType() throws {
        try loadTextEditorElement()
        let rtf = "{\\rtf1\\ansi {\\b Bold} text}"
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: rtf, contentType: "rtf")
        let value = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertNotNil(value as? AttributedString, "rtf contentType should store AttributedString in TextEditor")
        if let attr = value as? AttributedString {
            XCTAssertTrue(String(attr.characters).contains("Bold"))
        }
    }
    #endif
}
