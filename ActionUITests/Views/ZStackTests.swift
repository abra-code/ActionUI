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
    
    func testZStackConstruction() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ZStack",
            "properties": {
                "alignment": "center",
                "offset": {"x": 10.0, "y": -5.0}
            },
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Background"}},
                {"type": "Text", "id": 3, "properties": {"text": "Foreground"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = ZStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "ZStack should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "Alignment should be center")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 10.0, "offset.x should be 10.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
    }
    
    func testZStackJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ZStack",
            "properties": {
                "alignment": "topLeading",
                "offset": {"x": 15.0, "y": 20.0},
                "frame": {"width": 100.0, "height": 50.0, "alignment": "center"}
            },
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Background"}},
                {"type": "Text", "id": 3, "properties": {"text": "Foreground"}}
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
        XCTAssertEqual(element.type, "ZStack", "Element type should be ZStack")
        XCTAssertEqual(element.properties["alignment"] as? String, "topLeading", "Alignment should be topLeading")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), 20.0, "offset.y should be 20.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "frame.width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 50.0, "frame.height should be 50.0")
            XCTAssertEqual(frame["alignment"] as? String, "center", "frame.alignment should be center")
        } else {
            XCTFail("frame should be a dictionary")
        }
        
        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
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
    
    func testZStackWithCommonProperties() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ZStack",
            "properties": {
                "alignment": "topLeading",
                "offset": {"x": 15.0, "y": 20.0},
                "frame": {"width": 100.0, "height": 50.0, "alignment": "center"},
                "padding": 10.0,
                "opacity": 0.8
            },
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Background"}},
                {"type": "Text", "id": 3, "properties": {"text": "Foreground"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = ZStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElementBase] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "ZStack should have 2 children")
        XCTAssertEqual(validatedProperties["alignment"] as? String, "topLeading", "Alignment should be topLeading")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), 20.0, "offset.y should be 20.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "frame.width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 50.0, "frame.height should be 50.0")
            XCTAssertEqual(frame["alignment"] as? String, "center", "frame.alignment should be center")
        } else {
            XCTFail("frame should be a dictionary")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        XCTAssertEqual(element.properties.cgFloat(forKey: "opacity"), 0.8, "opacity should be 0.8")
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
    }
}
