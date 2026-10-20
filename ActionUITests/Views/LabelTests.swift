// Tests/Views/LabelTests.swift
/*
 LabelTests.swift

 Tests for the Label component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class LabelTests: XCTestCase {
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
    
    func testLabelConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Label",
            "properties": [
                "title": "Title",
                "systemImage": "star.fill",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)        
    }
    
    func testLabelJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Label",
            "properties": {
                "title": "Title",
                "systemImage": "star.fill",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
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
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Label", "Element type should be Label")
        XCTAssertEqual(element.properties["title"] as? String, "Title", "title should be Title")
        XCTAssertEqual(element.properties["systemImage"] as? String, "star.fill", "systemImage should be star.fill")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testLabelPropsValid() {
        let properties: [String: Any] = [
            "title": "Title",
            "systemImage": "star.fill",
            "padding": 10.0
        ]
        
        let props = Label.Props(properties)
        
        XCTAssertEqual(props.title, "Title", "title should be preserved")
        XCTAssertEqual(props.systemImage, "star.fill", "systemImage should be preserved")
        XCTAssertEqual(BaseModifiers(properties).padding, .uniform(10.0), "padding should be passed through")
    }
    
    func testLabelPropsIgnoreInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "systemImage": 456,
            "imageName": true
        ]
        
        let props = Label.Props(properties)
        
        XCTAssertEqual(props.title, "", "Invalid title should be ignored")
        XCTAssertNil(props.systemImage, "Invalid systemImage should be ignored")
        XCTAssertNil(props.imageName, "Invalid imageName should be ignored")
    }
    
    func testLabelPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Label.Props(properties)
        
        XCTAssertEqual(props.title, "", "Missing title should be empty")
        XCTAssertNil(props.systemImage, "Missing systemImage should be nil")
        XCTAssertNil(props.imageName, "Missing imageName should be nil")
    }
    
    func testLabelPropsTitleOnly() {
        let properties: [String: Any] = [
            "title": "Title"
        ]
        
        let props = Label.Props(properties)
        
        XCTAssertEqual(props.title, "Title", "title should be preserved")
        XCTAssertNil(props.systemImage, "Missing systemImage should be nil")
        XCTAssertNil(props.imageName, "Missing imageName should be nil")
    }
    
    func testLabelPropsImageName() {
        let properties: [String: Any] = [
            "title": "Title",
            "imageName": "customIcon"
        ]
        
        let props = Label.Props(properties)
        
        XCTAssertEqual(props.title, "Title", "title should be preserved")
        XCTAssertNil(props.systemImage, "Missing systemImage should be nil")
        XCTAssertEqual(props.imageName, "customIcon", "imageName should be preserved")
    }
}
