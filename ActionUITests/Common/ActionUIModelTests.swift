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
    
    func testSetAndGetElementValue() {
        let windowUUID = UUID().uuidString
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": ["placeholder": "Enter text"]
        ]
        
        let model = ActionUIModel.shared
        do {
            try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        } catch {
            XCTFail("Failed to load element from dictionary. Error: \(error)")
            return
        }

        model.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Test")
        let value = model.getElementValue(windowUUID: windowUUID, viewID: 1)
        
        logger.log("State for viewID 1: \(String(describing: model.states[windowUUID]?[1]))", .debug)
        XCTAssertEqual(value as? String, "Test", "Value should be set and retrieved correctly")
        XCTAssertEqual(
            (model.states[windowUUID]?[1] as? [String: Any])?["value"] as? String,
            "Test",
            "State should store value"
        )
    }
    
    func testSetElementProperty() {
        let windowUUID = UUID().uuidString
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": ["value": 0.5]
        ]
        
        let model = ActionUIModel.shared
        do {
            try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        } catch {
            XCTFail("Failed to load element from dictionary. Error: \(error)")
            return
        }

        model.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "value", value: 0.75)
        
        logger.log("State for viewID 1: \(String(describing: model.states[windowUUID]?[1]))", .debug)
        let viewState = model.states[windowUUID]?[1] as? [String: Any]
        let validatedProperties = viewState?["validatedProperties"] as? [String: Any]
        XCTAssertEqual(validatedProperties?["value"] as? Double, 0.75, "Property value should be updated")
    }
    
    func testFindElement() {
        let windowUUID = UUID().uuidString
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": [:],
            "children": [
                ["id": 2, "type": "TextField", "properties": ["placeholder": "Enter text"]]
            ]
        ]

        let model = ActionUIModel.shared
        do {
            try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        } catch {
            XCTFail("Failed to load element from dictionary. Error: \(error)")
            return
        }
        
        let foundElement = model.descriptions[windowUUID]?.findElement(by: 2)
        
        logger.log("Found element: \(String(describing: foundElement))", .debug)
        XCTAssertNotNil(foundElement, "Should find element with ID 2")
        XCTAssertEqual(foundElement?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(foundElement?.type, "TextField", "Found element should be TextField")
    }
    
    func testMissingElement() {
        let windowUUID = UUID().uuidString
        let model = ActionUIModel.shared
        model.setElementValue(windowUUID: windowUUID, viewID: 999, value: "Test")
        
        let value = model.getElementValue(windowUUID: windowUUID, viewID: 999)
        logger.log("State for viewID 999: \(String(describing: model.states[windowUUID]?[999]))", .debug)
        XCTAssertNil(value, "Value for missing element should be nil")
    }
}
