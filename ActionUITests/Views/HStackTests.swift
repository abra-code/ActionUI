// Tests/Views/HStackTests.swift
/*
 HStackTests.swift

 Tests for the HStack component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class HStackTests: XCTestCase {
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
    
    func testHStackConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": ["spacing": 10.0],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "HStack should have 2 children")
        XCTAssertEqual((children[0] as? ActionUIElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ActionUIElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ActionUIElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ActionUIElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testHStackJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "HStack",
            "properties": {"spacing": 10.0},
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
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "HStack", "Element type should be HStack")
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "Spacing should be 10.0")
        
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
    
    func testHStackPropsValid() {
        let properties: [String: Any] = ["spacing": 10.0]
        
        let props = HStack.Props(properties)
        
        XCTAssertEqual(props.spacing, 10.0, "Spacing should be valid")
    }
    
    func testHStackPropsIgnoreInvalidValues() {
        let properties: [String: Any] = ["spacing": "10"]
        
        let props = HStack.Props(properties)
        
        XCTAssertNil(props.spacing, "Invalid spacing should be nil")
    }
    
    func testHStackPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = HStack.Props(properties)
        
        XCTAssertNil(props.spacing, "Missing spacing should be nil")
    }
    
    func testHStackPropsAlignmentValid() {
        let validValues: [(String, ActionUI.HStack.Props.Alignment)] = [("top", .top), ("center", .center), ("bottom", .bottom), ("firstTextBaseline", .firstTextBaseline), ("lastTextBaseline", .lastTextBaseline)]
        for (value, alignment) in validValues {
            let props = HStack.Props(["alignment": value])
            XCTAssertEqual(props.alignment, alignment, "alignment '\(value)' should be preserved")
        }
    }

    func testHStackPropsAlignmentInvalid() {
        let props = HStack.Props(["alignment": "leading"])
        XCTAssertEqual(props.alignment, .center, "Invalid alignment 'leading' (horizontal, not vertical) should be ignored")

        let props2 = HStack.Props(["alignment": 42])
        XCTAssertEqual(props2.alignment, .center, "Non-string alignment should be ignored")
    }

    func testHStackConstructionWithAlignment() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": ["spacing": 8.0, "alignment": "top"],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "A"]],
                ["type": "Text", "id": 3, "properties": ["text": "B"]]
            ]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        XCTAssertEqual(HStack.Props(properties).alignment, .top)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
    }

    func testHStackNilSpacing() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]

        let element = try! ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        let children = element.subviews?["children"] as? [any ActionUIElementBase]
        XCTAssertEqual(children?.count, 2, "HStack should have 2 children")
        XCTAssertNil(HStack.Props(properties).spacing, "Spacing should be nil")
    }
}
