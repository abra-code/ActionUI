// Tests/Views/LazyHGridTests.swift
/*
 LazyHGridTests.swift

 Tests for the LazyHGrid component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LazyHGridTests: XCTestCase {
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
    
    func testLazyHGridConstruction() throws {
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
        let storedProperties = viewModel.properties
        let view = ActionUIRegistry.shared.buildView(
                        for: element,
                        model: viewModel,
                        windowUUID: windowUUID,
                        properties: storedProperties
                    )
        
        XCTAssertEqual(children.count, 2, "LazyHGrid should have 2 children")
        XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ActionUIElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ActionUIElement)?.id, 3, "Second child ID should be 3")
        XCTAssertTrue(view is SwiftUI.LazyHGrid<ForEach<[any ActionUIElementBase], Int, ActionUIView?>>, "View should be LazyHGrid")
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
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
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
    
    func testLazyHGridNilProperties() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "LazyHGrid",
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
        XCTAssertEqual(children.count, 2, "LazyHGrid should have 2 children")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Act: Create ActionUIView
        let storedProperties = viewModel.properties
        let view = ActionUIRegistry.shared.buildView(
                        for: element,
                        model: viewModel,
                        windowUUID: windowUUID,
                        properties: storedProperties
                    )
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "LazyHGrid should have 2 children")
        let props = LazyHGrid.Props(storedProperties)
        XCTAssertEqual(props.rows, [.flexible], "Rows should be the default")
        XCTAssertEqual(props.spacing, 0.0, "Spacing should be the default")
        XCTAssertEqual(props.alignment, .center, "Alignment should be the default")
        XCTAssertTrue(view is SwiftUI.LazyHGrid<ForEach<[any ActionUIElementBase], Int, ActionUIView?>>, "View should be LazyHGrid with default rows")
    }
    
    func testLazyHGridPropsRowsPartial() {
        let properties: [String: Any] = [
            "rows": [
                ["minimum": 100.0],
                ["flexible": true]
            ],
            "spacing": 10.0
        ]
        
        let props = LazyHGrid.Props(properties)
        
        XCTAssertEqual(props.rows, [.fixed(100.0), .flexible], "rows should have 2 valid entries")
        XCTAssertEqual(props.spacing, 10.0, "Spacing should be valid")
    }
    
    func testLazyHGridPropsRowsInvalid() {
        let properties: [String: Any] = [
            "rows": [
                ["minimum": "100"],
                ["flexible": "true"]
            ],
            "spacing": 10.0
        ]
        
        let props = LazyHGrid.Props(properties)
        
        XCTAssertEqual(props.rows, [.flexible], "Invalid rows should be ignored")
        XCTAssertEqual(props.spacing, 10.0, "Spacing should be valid")
    }
}
