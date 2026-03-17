// Tests/Views/TextFieldTests.swift
/*
 TextFieldTests.swift

 Tests for the TextField component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and textContentType application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextFieldTests: XCTestCase {
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
        
    func testTextFieldValidatePropertiesValid() {
        let properties: [String: Any] = [
            "prompt": "Enter text",
            "textContentType": "username",
            "actionID": "text.submit"
        ]

        let validated = TextField.validateProperties(properties, logger)

        XCTAssertEqual(validated["prompt"] as? String, "Enter text", "Prompt should be valid")
        XCTAssertEqual(validated["textContentType"] as? String, "username", "textContentType should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "text.submit", "actionID should be valid")
    }
    
    func testTextFieldValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "prompt": 123,
            "textContentType": 456
        ]

        let validated = TextField.validateProperties(properties, logger)

        XCTAssertNil(validated["prompt"], "Invalid prompt should be nil")
        XCTAssertNil(validated["textContentType"], "Invalid textContentType should be nil")
    }
    
    func testTextFieldValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TextField.validateProperties(properties, logger)
        
        XCTAssertNil(validated["prompt"], "Missing prompt should be nil")
        XCTAssertNil(validated["textContentType"], "Missing textContentType should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
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
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
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

    func testTextFieldTextPropertyValidation() {
        let valid = TextField.validateProperties(["text": "hello"], logger)
        XCTAssertEqual(valid["text"] as? String, "hello", "Valid text should be preserved")

        let invalid = TextField.validateProperties(["text": 123], logger)
        XCTAssertNil(invalid["text"], "Non-String text should be removed")
    }

    func testTextFieldInitialValueFromTextProperty() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["text": "prefilled"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "prefilled", "initialValue should fall back to text property")
    }

    func testTextFieldInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = "typed"
        viewModel.validatedProperties = ["text": "prefilled"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "typed", "initialValue should prefer model.value over text property")
    }

    // MARK: - Format property validation

    func testTextFieldFormatValidation() {
        let valid = TextField.validateProperties(["format": "integer"], logger)
        XCTAssertEqual(valid["format"] as? String, "integer", "Valid format should be preserved")

        let validDecimal = TextField.validateProperties(["format": "decimal"], logger)
        XCTAssertEqual(validDecimal["format"] as? String, "decimal")

        let validPercent = TextField.validateProperties(["format": "percent"], logger)
        XCTAssertEqual(validPercent["format"] as? String, "percent")

        let validCurrency = TextField.validateProperties(["format": "currency", "currencyCode": "EUR"], logger)
        XCTAssertEqual(validCurrency["format"] as? String, "currency")
        XCTAssertEqual(validCurrency["currencyCode"] as? String, "EUR")

        let invalidFormat = TextField.validateProperties(["format": "unknown"], logger)
        XCTAssertNil(invalidFormat["format"], "Invalid format should be removed")

        let nonStringFormat = TextField.validateProperties(["format": 123], logger)
        XCTAssertNil(nonStringFormat["format"], "Non-String format should be removed")
    }

    func testTextFieldFractionLengthValidation() {
        let exact = TextField.validateProperties(["format": "decimal", "fractionLength": 2], logger)
        XCTAssertEqual(exact["fractionLength"] as? Int, 2, "Exact fractionLength should be preserved")

        let range = TextField.validateProperties(["format": "decimal", "fractionLength": ["min": 0, "max": 3]], logger)
        XCTAssertNotNil(range["fractionLength"], "Range fractionLength should be preserved")

        let invalid = TextField.validateProperties(["format": "decimal", "fractionLength": "two"], logger)
        XCTAssertNil(invalid["fractionLength"], "Invalid fractionLength should be removed")
    }

    func testTextFieldValuePropertyValidation() {
        let intValue = TextField.validateProperties(["format": "integer", "value": 42], logger)
        XCTAssertEqual(intValue["value"] as? Int, 42, "Int value should be preserved")

        let doubleValue = TextField.validateProperties(["format": "decimal", "value": 3.14], logger)
        XCTAssertEqual(doubleValue["value"] as? Double, 3.14, "Double value should be preserved")

        let stringValue = TextField.validateProperties(["format": "integer", "value": "100"], logger)
        XCTAssertEqual(stringValue["value"] as? String, "100", "String value should be preserved")

        let invalidValue = TextField.validateProperties(["format": "integer", "value": [1, 2]], logger)
        XCTAssertNil(invalidValue["value"], "Array value should be removed")
    }

    // MARK: - Formatted TextField initial value

    func testTextFieldFormatInitialValueFromIntProperty() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["format": "integer", "value": 42]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "42", "initialValue should convert Int value to String")
    }

    func testTextFieldFormatInitialValueFromDoubleProperty() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["format": "decimal", "value": 3.14]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "3.14", "initialValue should convert Double value to String")
    }

    func testTextFieldFormatInitialValueDefault() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["format": "integer"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "0", "initialValue for formatted field should default to '0'")
    }

    // MARK: - Axis property validation

    func testTextFieldAxisValidation() {
        let vertical = TextField.validateProperties(["axis": "vertical"], logger)
        XCTAssertEqual(vertical["axis"] as? String, "vertical", "Valid vertical axis should be preserved")

        let horizontal = TextField.validateProperties(["axis": "horizontal"], logger)
        XCTAssertEqual(horizontal["axis"] as? String, "horizontal", "Valid horizontal axis should be preserved")

        let invalid = TextField.validateProperties(["axis": "diagonal"], logger)
        XCTAssertNil(invalid["axis"], "Invalid axis value should be removed")

        let nonString = TextField.validateProperties(["axis": 123], logger)
        XCTAssertNil(nonString["axis"], "Non-String axis should be removed")
    }

    // MARK: - LineLimit property validation

    func testTextFieldLineLimitExactValidation() {
        let exact = TextField.validateProperties(["lineLimit": 5], logger)
        XCTAssertEqual(exact["lineLimit"] as? Int, 5, "Exact lineLimit should be preserved")
    }

    func testTextFieldLineLimitRangeValidation() {
        let range = TextField.validateProperties(["lineLimit": ["min": 3, "max": 10]], logger)
        XCTAssertNotNil(range["lineLimit"], "Range lineLimit should be preserved")

        let minOnly = TextField.validateProperties(["lineLimit": ["min": 3]], logger)
        XCTAssertNotNil(minOnly["lineLimit"], "Min-only lineLimit should be preserved")

        let emptyDict = TextField.validateProperties(["lineLimit": ["foo": "bar"]], logger)
        XCTAssertNil(emptyDict["lineLimit"], "Dict without min/max should be removed")

        let invalid = TextField.validateProperties(["lineLimit": "five"], logger)
        XCTAssertNil(invalid["lineLimit"], "Non-Int/dict lineLimit should be removed")
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
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
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
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
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
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
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
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        viewModel.validatedProperties = validatedProperties
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
    }
}
