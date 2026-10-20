// Tests/Views/GridTests.swift
/*
 GridTests.swift

 Tests for the Grid component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and subview handling.

 Sample JSON for Grid:
 {
   "type": "Grid",
   "id": 1,
   "rows": [
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
    
    func testGridConstruction() throws {
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
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let rows = element.subviews?["rows"] as? [[any ActionUIElementBase]] else {
            XCTFail("Rows key not found in element.subviews dictionary")
            return
        }
        
        XCTAssertEqual(rows.count, 2, "Grid should have 2 rows")
        XCTAssertEqual(rows[0].count, 2, "First row should have 2 elements")
        XCTAssertEqual(rows[1].count, 1, "Second row should have 1 element")
        XCTAssertEqual((rows[0][0] as? ActionUIElement)?.type, "Text", "First cell should be Text")
        XCTAssertEqual((rows[0][0] as? ActionUIElement)?.id, 2, "First cell ID should be 2")
        XCTAssertEqual((rows[0][1] as? ActionUIElement)?.type, "Button", "Second cell should be Button")
        XCTAssertEqual((rows[0][1] as? ActionUIElement)?.id, 3, "Second cell ID should be 3")
        XCTAssertEqual((rows[1][0] as? ActionUIElement)?.type, "Image", "Third cell should be Image")
        XCTAssertEqual((rows[1][0] as? ActionUIElement)?.id, 4, "Third cell ID should be 4")
    }
    
    func testGridJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Grid",
            "rows": [
                [
                    {"type": "Text", "id": 2, "properties": {"text": "Cell1"}},
                    {"type": "Image", "id": 3, "properties": {"systemName": "star"}}
                ],
                [
                    {"type": "Button", "id": 4, "properties": {"title": "Click"}}
                ]
            ],
            "properties": {
                "alignment": "topLeading",
                "horizontalSpacing": 10.0,
                "verticalSpacing": 5.0
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
                
        logger.log("Raw rows: \(String(describing: element.subviews?["rows"]))", .debug)
        guard let rows = element.subviews?["rows"] as? [[any ActionUIElementBase]] else {
            XCTFail("Rows key not found in element.subviews dictionary")
            return
        }
        logger.log("Rows: \(String(describing: rows.map { $0.map { ($0 as? ActionUIElement)?.type ?? "nil" } }))", .debug)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Grid", "Element type should be Grid")
        XCTAssertEqual(rows.count, 2, "Rows should have 2 elements")
        XCTAssertEqual(rows[0].count, 2, "First row should have 2 elements")
        XCTAssertEqual(rows[1].count, 1, "Second row should have 1 element")
        XCTAssertEqual((rows[0][0] as? ActionUIElement)?.type, "Text", "First cell should be Text")
        XCTAssertEqual((rows[0][0] as? ActionUIElement)?.id, 2, "First cell ID should be 2")
        XCTAssertEqual((rows[0][1] as? ActionUIElement)?.type, "Image", "Second cell should be Image")
        XCTAssertEqual((rows[0][1] as? ActionUIElement)?.id, 3, "Second cell ID should be 3")
        XCTAssertEqual((rows[1][0] as? ActionUIElement)?.type, "Button", "Third cell should be Button")
        XCTAssertEqual((rows[1][0] as? ActionUIElement)?.id, 4, "Third cell ID should be 4")
        XCTAssertEqual(element.properties["alignment"] as? String, "topLeading", "Alignment should be topLeading")
        XCTAssertEqual(element.properties.cgFloat(forKey: "horizontalSpacing"), 10.0, "Horizontal spacing should be 10.0")
        XCTAssertEqual(element.properties.cgFloat(forKey: "verticalSpacing"), 5.0, "Vertical spacing should be 5.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
    }
    
    func testGridPropsValid() {
        let properties: [String: Any] = [
            "alignment": "center",
            "horizontalSpacing": 8.0,
            "verticalSpacing": 8.0
        ]
        
        let props = Grid.Props(properties)
        XCTAssertEqual(props.alignment, .center, "Alignment should be center")
        XCTAssertEqual(props.horizontalSpacing, 8.0, "Horizontal spacing should be valid")
        XCTAssertEqual(props.verticalSpacing, 8.0, "Vertical spacing should be valid")
    }
    
    func testGridPropsIgnoreInvalid() {
        let properties: [String: Any] = [
            "alignment": "invalid",
            "horizontalSpacing": "8",
            "verticalSpacing": "8"
        ]
        
        let props = Grid.Props(properties)
        
        XCTAssertEqual(props.alignment, .center, "Invalid alignment should be ignored")
        XCTAssertNil(props.horizontalSpacing, "Invalid horizontalSpacing should be ignored")
        XCTAssertNil(props.verticalSpacing, "Invalid verticalSpacing should be ignored")
    }
    
    func testGridPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Grid.Props(properties)
        
        XCTAssertEqual(props.alignment, .center, "Missing alignment should be the default")
        XCTAssertNil(props.horizontalSpacing, "Missing horizontalSpacing should be nil")
        XCTAssertNil(props.verticalSpacing, "Missing verticalSpacing should be nil")
    }
    
    func testGridNilSpacing() throws {
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
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)

        let props = Grid.Props(properties)
        XCTAssertNil(props.horizontalSpacing, "Horizontal spacing should be nil")
        XCTAssertNil(props.verticalSpacing, "Missing verticalSpacing should be nil")

        guard let rows = element.subviews?["rows"] as? [[any ActionUIElementBase]] else {
            XCTFail("Rows key not found in element.subviews dictionary")
            return
        }
        XCTAssertEqual(rows.count, 2, "Grid should have 2 rows")
    }
}
