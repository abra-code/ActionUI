// Tests/Common/ActionUIModelTests.swift
/*
 ActionUIModelTests.swift

 Tests for the ActionUIModel class in the ActionUI component library.
 Verifies state management, element lookup, and description storage without triggering actions.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIModelTests: XCTestCase {
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
    
    func testSetAndGetElementValue() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": ["placeholder": "Enter text"]
        ]
        
        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Test")
        let value = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "Test", "Value should be set and retrieved correctly")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[1] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        logger.log("Value for viewID 1: \(String(describing: viewModel.value))", .debug)
        XCTAssertEqual(viewModel.value as? String, "Test", "viewModel should store value")
    }
    
    func testSetElementProperty() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": ["value": 0.5]
        ]
        
        let actionUIModel = ActionUIModel.shared
        do {
            _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        } catch {
            XCTFail("Failed to load element from dictionary. Error: \(error)")
            return
        }

        actionUIModel.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "value", value: 0.75)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[1] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        logger.log("Value for viewID 1: \(String(describing: viewModel.value))", .debug)
        let validatedProperties = viewModel.validatedProperties
        XCTAssertEqual(validatedProperties.double(forKey: "value"), 0.75, "Property value should be updated")
    }
    
    func testFindElement() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": [:],
            "children": [
                ["id": 2, "type": "TextField", "properties": ["placeholder": "Enter text"]]
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)        
        let foundElement = element.findElement(by: 2)
        
        logger.log("Found element: \(String(describing: foundElement))", .debug)
        XCTAssertNotNil(foundElement, "Should find element with ID 2")
        XCTAssertEqual(foundElement?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(foundElement?.type, "TextField", "Found element should be TextField")
    }
    
    func testMissingElement() {
        let actionUIModel = ActionUIModel.shared
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: 999, value: "Test")
        
        let value = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: 999)
        XCTAssertNil(value, "Value for missing element should be nil")
    }
}
