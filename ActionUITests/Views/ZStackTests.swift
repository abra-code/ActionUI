// Tests/Views/ZStackTests.swift
/*
 ZStackTests.swift

 Tests for the ZStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
 Tests common SwiftUI.View properties (e.g., offset, frame) via ActionUIRegistry.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ZStackTests: XCTestCase {
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
    
    func testZStackConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ZStack",
            "properties": [
                "alignment": "center",
                "offset": ["x": 10.0, "y": -5.0]
            ],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Background"]],
                ["type": "Text", "id": 3, "properties": ["text": "Foreground"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ZStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
                
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "ZStack should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
        
        // Verify view is a ZStack (cannot check type directly due to opaque SwiftUI types)
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
    }
    
    func testZStackJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ZStack",
            "properties": [
                "alignment": "topLeading",
                "offset": ["x": 15.0, "y": 20.0],
                "frame": ["width": 100.0, "height": 50.0, "alignment": "center"]
            ],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Background"]],
                ["type": "Text", "id": 3, "properties": ["text": "Foreground"]]
            ]
        ]
        
        let element = try! ViewElement(from: elementDict, logger: logger)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "ZStack", "Element type should be ZStack")
        XCTAssertEqual(element.properties["alignment"] as? String, "topLeading", "Alignment should be topLeading")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), 20.0, "offset.y should be 20.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "Frame width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 50.0, "Frame height should be 50.0")
        } else {
            XCTFail("frame should be valid dictionary")
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
    
    func testZStackValidatePropertiesValid() {
        let properties: [String: Any] = ["alignment": "center"]
        
        let validated = ZStack.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["alignment"] as? String, "center", "Alignment should be valid")
    }
    
    func testZStackValidatePropertiesInvalid() {
        let properties: [String: Any] = ["alignment": "invalid"]
        
        let validated = ZStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["alignment"], "Invalid alignment should be nil")
    }
    
    func testZStackValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = ZStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["alignment"], "Missing alignment should be nil")
    }
    
    func testZStackWithCommonProperties() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ZStack",
            "properties": [
                "alignment": "topLeading",
                "offset": ["x": 15.0, "y": 20.0],
                "frame": ["width": 100.0, "height": 50.0, "alignment": "center"],
                "padding": 10.0,
                "opacity": 0.8
            ],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Background"]],
                ["type": "Text", "id": 3, "properties": ["text": "Foreground"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = ZStack.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "ZStack should have 2 children")
        XCTAssertEqual(validatedProperties["alignment"] as? String, "topLeading", "Alignment should be topLeading")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), 20.0, "offset.y should be 20.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "Frame width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 50.0, "Frame height should be 50.0")
        } else {
            XCTFail("frame should be valid dictionary")
        }
        XCTAssertEqual(element.properties.double(forKey: "opacity"), 0.8, "Opacity should be 0.8")
    }
}
