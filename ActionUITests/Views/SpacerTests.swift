// Tests/Views/SpacerTests.swift
/*
 SpacerTests.swift

 Tests for the Spacer component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SpacerTests: XCTestCase {
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
    
    func testSpacerPropsValid() {
        let properties: [String: Any] = [
            "minLength": 20.0,
            "padding": 10.0
        ]
        
        let props = Spacer.Props(properties)
        
        XCTAssertEqual(props.minLength, 20.0, "minLength should be valid")
        XCTAssertEqual(BaseModifiers(properties).padding, .uniform(10.0), "padding should be read by BaseModifiers")
    }
    
    func testSpacerPropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "minLength": "invalid"
        ]
        
        let props = Spacer.Props(properties)
        
        XCTAssertNil(props.minLength, "Invalid minLength should be ignored")
    }
    
    func testSpacerPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Spacer.Props(properties)
        
        XCTAssertNil(props.minLength, "Missing minLength should be nil")
    }
    
    func testSpacerConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Spacer",
            "properties": [
                "minLength": 20.0,
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testSpacerJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Spacer",
            "properties": {
                "minLength": 20.0,
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
        XCTAssertEqual(element.type, "Spacer", "Element type should be Spacer")
        XCTAssertEqual(element.properties.cgFloat(forKey: "minLength"), 20.0, "minLength should be 20.0")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.value, "Initial viewModel value should be nil for Spacer")
    }
}
