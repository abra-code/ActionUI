// Tests/Views/TextFieldTests.swift
/*
 TextFieldTests.swift

 Tests for the TextField component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, state binding, and textContentType application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextFieldTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
        
    func testTextFieldPropsValid() {
        let properties: [String: Any] = [
            "prompt": "Enter text",
            "textContentType": "username",
            "actionID": "text.submit"
        ]

        let props = TextField.Props(properties)

        XCTAssertEqual(props.prompt, "Enter text", "Prompt should be valid")
        XCTAssertEqual(props.textContentType, "username", "textContentType should be valid")
        XCTAssertEqual(props.actionID, "text.submit", "actionID should be valid")
    }
    
    func testTextFieldPropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "prompt": 123,
            "textContentType": 456
        ]

        let props = TextField.Props(properties)

        XCTAssertNil(props.prompt, "Invalid prompt should be ignored")
        XCTAssertNil(props.textContentType, "Invalid textContentType should be ignored")
    }
    
    func testTextFieldPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = TextField.Props(properties)
        
        XCTAssertNil(props.prompt, "Missing prompt should be nil")
        XCTAssertNil(props.textContentType, "Missing textContentType should be nil")
        XCTAssertNil(props.actionID, "Missing actionID should be nil")
    }
    
    func testTextFieldConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [
                "prompt": "Enter text",
                "textContentType": "username",
                "actionID": "text.submit",
                "padding": 10.0
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTextFieldJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TextField",
            "properties": {
                "prompt": "Enter text",
                "textContentType": "username",
                "actionID": "text.submit",
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
        XCTAssertEqual(element.type, "TextField", "Element type should be TextField")
        XCTAssertEqual(element.properties["prompt"] as? String, "Enter text", "prompt should be Enter text")
        XCTAssertEqual(element.properties["textContentType"] as? String, "username", "textContentType should be username")
        XCTAssertEqual(element.properties["actionID"] as? String, "text.submit", "actionID should be text.submit")
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

    func testTextFieldPropsText() {
        let valid = TextField.Props(["text": "hello"])
        XCTAssertEqual(valid.text, "hello", "Valid text should be preserved")

        let invalid = TextField.Props(["text": 123])
        XCTAssertNil(invalid.text, "Non-String text should be ignored")
    }

    func testTextFieldInitialValueFromTextProperty() {
        let viewModel = ViewModel()
        viewModel.properties = ["text": "prefilled"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "prefilled", "initialValue should fall back to text property")
    }

    func testTextFieldInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = "typed"
        viewModel.properties = ["text": "prefilled"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "typed", "initialValue should prefer model.value over text property")
    }

    // MARK: - Format property

    func testTextFieldPropsFormat() {
        let valid = TextField.Props(["format": "integer"])
        XCTAssertEqual(valid.format, .integer, "Valid format should be preserved")

        let validDecimal = TextField.Props(["format": "decimal"])
        XCTAssertEqual(validDecimal.format, .decimal(minFraction: nil, maxFraction: nil))

        let validPercent = TextField.Props(["format": "percent"])
        XCTAssertEqual(validPercent.format, .percent(minFraction: nil, maxFraction: nil))

        let validCurrency = TextField.Props(["format": "currency", "currencyCode": "EUR"])
        XCTAssertEqual(validCurrency.format, .currency(code: "EUR", minFraction: nil, maxFraction: nil))

        let invalidFormat = TextField.Props(["format": "unknown"])
        XCTAssertNil(invalidFormat.format, "Invalid format should be ignored")

        let nonStringFormat = TextField.Props(["format": 123])
        XCTAssertNil(nonStringFormat.format, "Non-String format should be ignored")
    }

    func testTextFieldPropsFractionLength() {
        let exact = TextField.Props(["format": "decimal", "fractionLength": 2])
        XCTAssertEqual(exact.format, .decimal(minFraction: 2, maxFraction: 2), "Exact fractionLength should be preserved")

        let range = TextField.Props(["format": "decimal", "fractionLength": ["min": 0, "max": 3]])
        XCTAssertEqual(range.format, .decimal(minFraction: 0, maxFraction: 3), "Range fractionLength should be preserved")

        let invalid = TextField.Props(["format": "decimal", "fractionLength": "two"])
        XCTAssertEqual(invalid.format, .decimal(minFraction: nil, maxFraction: nil), "Invalid fractionLength should be ignored")
    }

    func testTextFieldPropsValue() {
        let intValue = TextField.Props(["format": "integer", "value": 42])
        XCTAssertEqual(intValue.formattedInitialValue, "42", "Int value should be preserved")

        let doubleValue = TextField.Props(["format": "decimal", "value": 3.14])
        XCTAssertEqual(doubleValue.formattedInitialValue, "3.14", "Double value should be preserved")

        let stringValue = TextField.Props(["format": "integer", "value": "100"])
        XCTAssertEqual(stringValue.formattedInitialValue, "100", "String value should be preserved")

        let invalidValue = TextField.Props(["format": "integer", "value": [1, 2]])
        XCTAssertEqual(invalidValue.formattedInitialValue, "0", "Array value should be ignored")
    }

    // MARK: - Formatted TextField initial value

    func testTextFieldFormatInitialValueFromIntProperty() {
        let viewModel = ViewModel()
        viewModel.properties = ["format": "integer", "value": 42]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "42", "initialValue should convert Int value to String")
    }

    func testTextFieldFormatInitialValueFromDoubleProperty() {
        let viewModel = ViewModel()
        viewModel.properties = ["format": "decimal", "value": 3.14]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "3.14", "initialValue should convert Double value to String")
    }

    func testTextFieldFormatInitialValueDefault() {
        let viewModel = ViewModel()
        viewModel.properties = ["format": "integer"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "0", "initialValue for formatted field should default to '0'")
    }

    // MARK: - Axis property

    func testTextFieldPropsAxis() {
        let vertical = TextField.Props(["axis": "vertical"])
        XCTAssertEqual(vertical.axis, .vertical, "Valid vertical axis should be preserved")

        let horizontal = TextField.Props(["axis": "horizontal"])
        XCTAssertEqual(horizontal.axis, .horizontal, "Valid horizontal axis should be preserved")

        let invalid = TextField.Props(["axis": "diagonal"])
        XCTAssertNil(invalid.axis, "Invalid axis value should be ignored")

        let nonString = TextField.Props(["axis": 123])
        XCTAssertNil(nonString.axis, "Non-String axis should be ignored")
    }

    // MARK: - LineLimit property

    func testTextFieldPropsLineLimitExact() {
        let exact = TextField.Props(["lineLimit": 5])
        XCTAssertEqual(exact.lineLimit, .exact(5), "Exact lineLimit should be preserved")
    }

    func testTextFieldPropsLineLimitRange() {
        let range = TextField.Props(["lineLimit": ["min": 3, "max": 10]])
        XCTAssertEqual(range.lineLimit, .range(min: 3, max: 10), "Range lineLimit should be preserved")

        let minOnly = TextField.Props(["lineLimit": ["min": 3]])
        XCTAssertEqual(minOnly.lineLimit, .range(min: 3, max: nil), "Min-only lineLimit should be preserved")

        let emptyDict = TextField.Props(["lineLimit": ["foo": "bar"]])
        XCTAssertNil(emptyDict.lineLimit, "Dict without min/max should be ignored")

        let invalid = TextField.Props(["lineLimit": "five"])
        XCTAssertNil(invalid.lineLimit, "Non-Int/dict lineLimit should be ignored")
    }

    // MARK: - Vertical TextField construction

    func testTextFieldVerticalConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [
                "prompt": "Enter description...",
                "axis": "vertical",
                "lineLimit": ["min": 3, "max": 10]
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
    }

    // MARK: - Formatted TextField construction

    func testTextFieldIntegerFormatConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [
                "title": "Quantity",
                "format": "integer",
                "value": 10
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
    }

    func testTextFieldCurrencyFormatConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [
                "title": "Price",
                "format": "currency",
                "currencyCode": "USD",
                "fractionLength": ["min": 2, "max": 2],
                "value": 9.99
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
    }

    func testTextFieldPercentFormatConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [
                "title": "Rate",
                "format": "percent",
                "value": 0.15
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.properties = properties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
    }
}
