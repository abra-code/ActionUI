// Tests/Views/GridTests.swift
/*
 GridTests.swift

 Tests for the Grid component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.

 Sample JSON for Grid:
 {
   "type": "Grid",
   "id": 1,
   "rows": [             // Note: Declared as a top-level key in JSON but stored in subviews["rows"] by StaticElement.init(from:).
     [
       { "type": "Text", "id": 2, "properties": { "text": "Cell1" } },
       { "type": "Button", "id": 3, "properties": { "title": "Click" } }
     ],
     [
       { "type": "Image", "id": 4, "properties": { "systemName": "star" } }
     ]
   ],
   "properties": {
     "alignment": "center",
     "horizontalSpacing": 8.0,
     "verticalSpacing": 8.0
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class GridTests: XCTestCase {
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
    
    func testGridConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Grid",
            "rows": [
                [
                    ["type": "Text", "id": 2, "properties": ["text": "Cell1"]],
                    ["type": "Button", "id": 3, "properties": ["title": "Click"]]
                ],
                [
                    ["type": "Image", "id": 4, "properties": ["systemName": "star"]]
                ]
            ],
            "properties": [
                "alignment": "center",
                "horizontalSpacing": 8.0,
                "verticalSpacing": 8.0
            ]
        ]
        let element = try! StaticElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Grid.validateProperties(element.properties, logger)
        
        let _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let rows = element.subviews?["rows"] as? [[any ActionUIElement]] else {
            XCTFail("Rows key not found in element.subviews dictionary")
            return
        }
        
        XCTAssertEqual(rows.count, 2, "Grid should have 2 rows")
        XCTAssertEqual(rows[0].count, 2, "First row should have 2 elements")
        XCTAssertEqual(rows[1].count, 1, "Second row should have 1 element")
        XCTAssertEqual((rows[0][0] as? StaticElement)?.type, "Text", "First cell should be Text")
        XCTAssertEqual((rows[0][0] as? StaticElement)?.id, 2, "First cell ID should be 2")
        XCTAssertEqual((rows[0][1] as? StaticElement)?.type, "Button", "Second cell should be Button")
        XCTAssertEqual((rows[0][1] as? StaticElement)?.id, 3, "Second cell ID should be 3")
        XCTAssertEqual((rows[1][0] as? StaticElement)?.type, "Image", "Third cell should be Image")
        XCTAssertEqual((rows[1][0] as? StaticElement)?.id, 4, "Third cell ID should be 4")
    }
    
    func testGridJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Grid",
            "rows": [
                [
                    ["type": "Text", "id": 2, "properties": ["text": "Cell1"]],
                    ["type": "Image", "id": 3, "properties": ["systemName": "star"]]
                ],
                [
                    ["type": "Button", "id": 4, "properties": ["title": "Click"]]
                ]
            ],
            "properties": [
                "alignment": "topLeading",
                "horizontalSpacing": 10.0,
                "verticalSpacing": 5.0
            ]
        ]
        
        do {
            let element = try StaticElement(from: elementDict)
            logger.log("Raw rows: \(String(describing: element.subviews?["rows"]))", .debug)
            let _ = Grid.validateProperties(element.properties, logger)
            guard let rows = element.subviews?["rows"] as? [[any ActionUIElement]] else {
                XCTFail("Rows key not found in element.subviews dictionary")
                return
            }
            logger.log("Rows: \(String(describing: rows.map { $0.map { ($0 as? StaticElement)?.type ?? "nil" } }))", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "Grid", "Element type should be Grid")
            XCTAssertEqual(rows.count, 2, "Rows should have 2 elements")
            XCTAssertEqual(rows[0].count, 2, "First row should have 2 elements")
            XCTAssertEqual(rows[1].count, 1, "Second row should have 1 element")
            XCTAssertEqual((rows[0][0] as? StaticElement)?.type, "Text", "First cell should be Text")
            XCTAssertEqual((rows[0][0] as? StaticElement)?.id, 2, "First cell ID should be 2")
            XCTAssertEqual((rows[0][1] as? StaticElement)?.type, "Image", "Second cell should be Image")
            XCTAssertEqual((rows[0][1] as? StaticElement)?.id, 3, "Second cell ID should be 3")
            XCTAssertEqual((rows[1][0] as? StaticElement)?.type, "Button", "Third cell should be Button")
            XCTAssertEqual((rows[1][0] as? StaticElement)?.id, 4, "Third cell ID should be 4")
            XCTAssertEqual((element.properties["alignment"] as? String), "topLeading", "Alignment should be topLeading")
            XCTAssertEqual((element.properties["horizontalSpacing"] as? Double), 10.0, "Horizontal spacing should be 10.0")
            XCTAssertEqual((element.properties["verticalSpacing"] as? Double), 5.0, "Vertical spacing should be 5.0")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
    
    func testGridValidatePropertiesValid() {
        let properties: [String: Any] = [
            "alignment": "center",
            "horizontalSpacing": 8.0,
            "verticalSpacing": 8.0
        ]
        
        let validateProperties = Grid.validateProperties(properties, logger)
        XCTAssertEqual(validateProperties["alignment"] as? String, "center", "Alignment should be valid")
        XCTAssertEqual(validateProperties["horizontalSpacing"] as? Double, 8.0, "Horizontal spacing should be valid")
        XCTAssertEqual(validateProperties["verticalSpacing"] as? Double, 8.0, "Vertical spacing should be valid")
    }
    
    func testGridValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "alignment": "invalid",
            "horizontalSpacing": "8",
            "verticalSpacing": "8"
        ]
        
        let validateProperties = Grid.validateProperties(properties, logger)
        
        XCTAssertNil(validateProperties["alignment"], "Invalid alignment should be nil")
        XCTAssertNil(validateProperties["horizontalSpacing"], "Invalid horizontalSpacing should be nil")
        XCTAssertNil(validateProperties["verticalSpacing"], "Invalid verticalSpacing should be nil")
    }
    
    func testGridValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validateProperties = Grid.validateProperties(properties, logger)
        
        XCTAssertNil(validateProperties["alignment"], "Missing alignment should be nil")
        XCTAssertNil(validateProperties["horizontalSpacing"], "Missing horizontalSpacing should be nil")
        XCTAssertNil(validateProperties["verticalSpacing"], "Missing verticalSpacing should be nil")
    }
    
    func testGridNilSpacing() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Grid",
            "rows": [
                [
                    ["type": "Text", "id": 2, "properties": ["text": "Cell1"]],
                    ["type": "Button", "id": 3, "properties": ["title": "Click"]]
                ],
                [
                    ["type": "Image", "id": 4, "properties": ["systemName": "star"]]
                ]
            ],
            "properties": [
                "alignment": "center"
            ]
        ]
        let element = try! StaticElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Grid.validateProperties(element.properties, logger)
        
        let _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)

        XCTAssertNil(validatedProperties["horizontalSpacing"], "Horizontal spacing should be nil")
        XCTAssertNil(validatedProperties["verticalSpacing"], "Vertical spacing should be nil")

        guard let rows = element.subviews?["rows"] as? [[any ActionUIElement]] else {
            XCTFail("Rows key not found in element.subviews dictionary")
            return
        }
        XCTAssertEqual(rows.count, 2, "Grid should have 2 rows")
    }
}
