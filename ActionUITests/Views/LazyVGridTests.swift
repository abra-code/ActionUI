// Tests/Views/LazyVGridTests.swift
/*
 LazyVGridTests.swift

 Tests for the LazyVGrid component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LazyVGridTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        super.tearDown()
    }
    
    func testLazyVGridConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyVGrid",
            "properties": [
                "columns": [
                    ["minimum": 100.0],
                    ["flexible": true]
                ],
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
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = LazyVGrid.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "LazyVGrid should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
        XCTAssertTrue(view is SwiftUI.LazyVGrid<ForEach<[any ActionUIElement], Int, ActionUIView>>, "View should be LazyVGrid")
    }
    
    func testLazyVGridJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyVGrid",
            "properties": [
                "columns": [
                    ["minimum": 100.0],
                    ["flexible": true]
                ],
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
        
        let element = try! ViewElement(from: elementDict, logger: logger)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "LazyVGrid", "Element type should be LazyVGrid")
        if let columns = element.properties["columns"] as? [[String: Any]] {
            XCTAssertEqual(columns.count, 2, "columns should have 2 entries")
            XCTAssertEqual(columns[0].cgFloat(forKey: "minimum"), 100.0, "columns[0].minimum should be 100.0")
            XCTAssertEqual(columns[1]["flexible"] as? Bool, true, "columns[1].flexible should be true")
        } else {
            XCTFail("columns should be valid array of dictionaries")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "Spacing should be 10.0")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "Alignment should be center")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "Children should have 2 elements")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testLazyVGridValidatePropertiesValid() {
        let properties: [String: Any] = [
            "columns": [
                ["minimum": 100.0],
                ["flexible": true]
            ],
            "spacing": 10.0,
            "alignment": "center",
            "padding": 20.0,
            "offset": ["x": 15.0, "y": -5.0]
        ]
        
        let validated = LazyVGrid.validateProperties(properties, logger)
        
        if let columns = validated["columns"] as? [[String: Any]] {
            XCTAssertEqual(columns.count, 2, "columns should have 2 valid entries")
            XCTAssertEqual(columns[0].cgFloat(forKey: "minimum"), 100.0, "columns[0].minimum should be valid")
            XCTAssertEqual(columns[1]["flexible"] as? Bool, true, "columns[1].flexible should be valid")
        } else {
            XCTFail("columns should be valid array of dictionaries")
        }
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
    
    func testLazyVGridValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "columns": [
                ["minimum": "100"],
                ["flexible": "true"]
            ],
            "spacing": "10",
            "alignment": "invalid"
        ]
        
        let validated = LazyVGrid.validateProperties(properties, logger)
        
        XCTAssertNil(validated["columns"], "Invalid columns should be nil")
        XCTAssertNil(validated["spacing"], "Invalid spacing should be nil")
        XCTAssertNil(validated["alignment"], "Invalid alignment should be nil")
    }
    
    func testLazyVGridValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = LazyVGrid.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Empty properties should result in empty validated properties")
        XCTAssertNil(validated["columns"], "Missing columns should be nil")
        XCTAssertNil(validated["spacing"], "Missing spacing should be nil")
        XCTAssertNil(validated["alignment"], "Missing alignment should be nil")
    }
    
    func testLazyVGridNilProperties() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyVGrid",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = LazyVGrid.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "LazyVGrid should have 2 children")
        XCTAssertNil(validatedProperties["columns"], "Columns should be nil")
        XCTAssertNil(validatedProperties["spacing"], "Spacing should be nil")
        XCTAssertNil(validatedProperties["alignment"], "Alignment should be nil")
        XCTAssertTrue(view is SwiftUI.LazyVGrid<ForEach<[any ActionUIElement], Int, ActionUIView>>, "View should be LazyVGrid with default columns")
    }
    
    func testLazyVGridValidatePropertiesColumnsPartial() {
        let properties: [String: Any] = [
            "columns": [
                ["minimum": 100.0],
                ["flexible": true]
            ],
            "spacing": 10.0,
            "offset": ["x": 15.0]
        ]
        
        let validated = LazyVGrid.validateProperties(properties, logger)
        
        if let columns = validated["columns"] as? [[String: Any]] {
            XCTAssertEqual(columns.count, 2, "columns should have 2 valid entries")
            XCTAssertEqual(columns[0].cgFloat(forKey: "minimum"), 100.0, "columns[0].minimum should be valid")
            XCTAssertNil(columns[0]["flexible"], "columns[0].flexible should be nil")
            XCTAssertEqual(columns[1]["flexible"] as? Bool, true, "columns[1].flexible should be valid")
            XCTAssertNil(columns[1]["minimum"], "columns[1].minimum should be nil")
        } else {
            XCTFail("columns should be valid array of dictionaries")
        }
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "Spacing should be valid")
        if let offset = validated["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be valid")
            XCTAssertNil(offset["y"], "offset.y should be nil")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testLazyVGridValidatePropertiesColumnsInvalid() {
        let properties: [String: Any] = [
            "columns": [
                ["minimum": "100"],
                ["flexible": "true"]
            ],
            "spacing": 10.0,
            "offset": ["x": 15.0, "y": -5.0]
        ]
        
        let validated = LazyVGrid.validateProperties(properties, logger)
        
        XCTAssertNil(validated["columns"], "Invalid columns should be nil")
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "Spacing should be valid")
        if let offset = validated["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be valid")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be valid")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
}
