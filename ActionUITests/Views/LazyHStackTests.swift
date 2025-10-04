// Tests/Views/LazyHStackTests.swift
/*
 LazyHStackTests.swift

 Tests for the LazyHStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LazyHStackTests: XCTestCase {
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
    
    func testLazyHStackConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyHStack",
            "properties": [
                "spacing": 10.0,
                "alignment": "center",
                "padding": 20.0,
                "offset": ["x": 15.0, "y": -5.0]
            ],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Act: Create ActionUIView
        let validatedProperties = viewModel.validatedProperties
        let view = ActionUIRegistry.shared.buildView(
                        for: element,
                        model: viewModel,
                        windowUUID: windowUUID,
                        validatedProperties: validatedProperties
                    )

        XCTAssertEqual(children.count, 2, "LazyHStack should have 2 children")
        XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ActionUIElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ActionUIElement)?.id, 3, "Second child ID should be 3")
        XCTAssertTrue(view is SwiftUI.LazyHStack<ForEach<[any ActionUIElementBase], Int, ActionUIView?>>, "View should be LazyHStack")
    }
    
    func testLazyHStackJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "LazyHStack",
            "properties": {
                "spacing": 10.0,
                "alignment": "center",
                "padding": 20.0,
                "offset": {"x": 15.0, "y": -5.0}
            },
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Item 1"}},
                {"type": "Text", "id": 3, "properties": {"text": "Item 2"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "LazyHStack", "Element type should be LazyHStack")
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "Spacing should be 10.0")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "Alignment should be center")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 20.0, "Padding should be 20.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "Children should have 2 elements")
        XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ActionUIElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ActionUIElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testLazyHStackValidatePropertiesValid() {
        let properties: [String: Any] = [
            "spacing": 10.0,
            "alignment": "center",
            "padding": 20.0,
            "offset": ["x": 15.0, "y": -5.0]
        ]
        
        let validated = LazyHStack.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "Spacing should be valid")
        XCTAssertEqual(validated["alignment"] as? String, "center", "Alignment should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 20.0, "Padding should be valid")
        if let offset = validated["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be valid")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be valid")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testLazyHStackValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "spacing": "10",
            "alignment": "invalid"
        ]
        
        let validated = LazyHStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["spacing"], "Invalid spacing should be nil")
        XCTAssertNil(validated["alignment"], "Invalid alignment should be nil")
    }
    
    func testLazyHStackValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = LazyHStack.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Empty properties should result in empty validated properties")
        XCTAssertNil(validated["spacing"], "Missing spacing should be nil")
        XCTAssertNil(validated["alignment"], "Missing alignment should be nil")
    }
    
    func testLazyHStackNilProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyHStack",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Act: Create ActionUIView
        let validatedProperties = viewModel.validatedProperties
        let view = ActionUIRegistry.shared.buildView(
                        for: element,
                        model: viewModel,
                        windowUUID: windowUUID,
                        validatedProperties: validatedProperties
                    )

        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertEqual(children.count, 2, "LazyHStack should have 2 children")
        XCTAssertNil(validatedProperties["spacing"], "Spacing should be nil")
        XCTAssertNil(validatedProperties["alignment"], "Alignment should be nil")
        XCTAssertTrue(view is SwiftUI.LazyHStack<ForEach<[any ActionUIElementBase], Int, ActionUIView?>>, "View should be LazyHStack")
    }
}
