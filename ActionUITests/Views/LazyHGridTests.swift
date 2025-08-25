// Tests/Views/LazyHGridTests.swift
/*
 LazyHGridTests.swift

 Tests for the LazyHGrid component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LazyHGridTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
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
    
    func testLazyHGridConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyHGrid",
            "properties": [
                "rows": [
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
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = LazyHGrid.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "LazyHGrid should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
        XCTAssertTrue(view is SwiftUI.LazyHGrid<ForEach<[any ActionUIElement], Int, ActionUIView>>, "View should be LazyHGrid")
    }
    
    func testLazyHGridJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "LazyHGrid",
            "properties": {
                "rows": [
                    {"minimum": 100.0},
                    {"flexible": true}
                ],
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
        
        let model = ActionUIModel.shared
        
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "LazyHGrid", "Element type should be LazyHGrid")
        if let rows = element.properties["rows"] as? [[String: Any]] {
            XCTAssertEqual(rows.count, 2, "rows should have 2 valid entries")
            XCTAssertEqual(rows[0].cgFloat(forKey: "minimum"), 100.0, "rows[0].minimum should be 100.0")
            XCTAssertNil(rows[0]["flexible"], "rows[0].flexible should be nil")
            XCTAssertEqual(rows[1]["flexible"] as? Bool, true, "rows[1].flexible should be true")
            XCTAssertNil(rows[1]["minimum"], "rows[1].minimum should be nil")
        } else {
            XCTFail("rows should be valid array of dictionaries")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "Spacing should be 10.0")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "Alignment should be center")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 20.0, "Padding should be 20.0")
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
    
    func testLazyHGridNilProperties() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyHGrid",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = LazyHGrid.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "LazyHGrid should have 2 children")
        XCTAssertNil(validatedProperties["rows"], "Rows should be nil")
        XCTAssertNil(validatedProperties["spacing"], "Spacing should be nil")
        XCTAssertNil(validatedProperties["alignment"], "Alignment should be nil")
        XCTAssertTrue(view is SwiftUI.LazyHGrid<ForEach<[any ActionUIElement], Int, ActionUIView>>, "View should be LazyHGrid with default rows")
    }
    
    func testLazyHGridValidatePropertiesRowsPartial() {
        let properties: [String: Any] = [
            "rows": [
                ["minimum": 100.0],
                ["flexible": true]
            ],
            "spacing": 10.0
        ]
        
        let validated = LazyHGrid.validateProperties(properties, logger)
        
        if let rows = validated["rows"] as? [[String: Any]] {
            XCTAssertEqual(rows.count, 2, "rows should have 2 valid entries")
            XCTAssertEqual(rows[0].cgFloat(forKey: "minimum"), 100.0, "rows[0].minimum should be valid")
            XCTAssertNil(rows[0]["flexible"], "rows[0].flexible should be nil")
            XCTAssertEqual(rows[1]["flexible"] as? Bool, true, "rows[1].flexible should be valid")
            XCTAssertNil(rows[1]["minimum"], "rows[1].minimum should be nil")
        } else {
            XCTFail("rows should be valid array of dictionaries")
        }
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "Spacing should be valid")
    }
    
    func testLazyHGridValidatePropertiesRowsInvalid() {
        let properties: [String: Any] = [
            "rows": [
                ["minimum": "100"],
                ["flexible": "true"]
            ],
            "spacing": 10.0
        ]
        
        let validated = LazyHGrid.validateProperties(properties, logger)
        
        XCTAssertNil(validated["rows"], "Invalid rows should be nil")
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "Spacing should be valid")
    }
}
