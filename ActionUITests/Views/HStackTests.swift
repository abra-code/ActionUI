// Tests/Views/HStackTests.swift
/*
 HStackTests.swift

 Tests for the HStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class HStackTests: XCTestCase {
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
    
    func testHStackConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": ["spacing": 10.0],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        let element = try! StaticElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = HStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        // Note: Redundant check, as buildView always returns any SwiftUI.View; child assertions provide specificity
        XCTAssertTrue(view is any SwiftUI.View, "View should be a SwiftUI view")
        
        XCTAssertEqual(element.children?.count, 2, "HStack should have 2 children")
        XCTAssertEqual((element.children?[0] as? StaticElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((element.children?[0] as? StaticElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((element.children?[1] as? StaticElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((element.children?[1] as? StaticElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testHStackJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": ["spacing": 10.0],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let element = try! StaticElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "HStack", "Element type should be HStack")
        XCTAssertEqual(element.properties["spacing"] as? Double, 10.0, "Spacing should be 10.0")
        XCTAssertEqual(element.children?.count, 2, "Children should have 2 elements")
        XCTAssertEqual((element.children?[0] as? StaticElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((element.children?[0] as? StaticElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((element.children?[1] as? StaticElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((element.children?[1] as? StaticElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testHStackValidatePropertiesValid() {
        let properties: [String: Any] = ["spacing": 10.0]
        
        let validated = HStack.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["spacing"] as? Double, 10.0, "Spacing should be valid")
    }
    
    func testHStackValidatePropertiesInvalid() {
        let properties: [String: Any] = ["spacing": "10"]
        
        let validated = HStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["spacing"], "Invalid spacing should be nil")
    }
    
    func testHStackValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = HStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["spacing"], "Missing spacing should be nil")
    }
    
    func testHStackNilSpacing() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        let element = try! StaticElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = HStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        // Note: Redundant check, as buildView always returns any SwiftUI.View; child assertions provide specificity
        XCTAssertTrue(view is any SwiftUI.View, "View should be a SwiftUI view")
        
        XCTAssertEqual(element.children?.count, 2, "HStack should have 2 children")
        XCTAssertNil(validatedProperties["spacing"], "Spacing should be nil")
    }
}
