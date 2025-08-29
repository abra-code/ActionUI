// Tests/Views/PhaseAnimatorTests.swift
/*
 PhaseAnimatorTests.swift

 Tests for the PhaseAnimator component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for PhaseAnimator:
 {
   "type": "PhaseAnimator",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Animating" }
   },
   "properties": {
     "values": [0.0, 1.0, 2.0],
     "trigger": "onAppear",
     "animation": { "type": "spring", "response": 0.5, "dampingFraction": 0.7 }
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class PhaseAnimatorTests: XCTestCase {
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
    
    func testPhaseAnimatorJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "PhaseAnimator",
            "content": {"type": "Text", "id": 2, "properties": {"text": "Animating"}},
            "properties": {
                "values": [0.0, 1.0, 2.0],
                "trigger": "onAppear",
                "animation": {"type": "spring", "response": 0.5, "dampingFraction": 0.7}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = PhaseAnimator.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        let content = element.subviews?["content"] as? any ActionUIElement
        let animation = element.properties["animation"] as? [String: Any]
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "PhaseAnimator", "Element type should be PhaseAnimator")
        XCTAssertEqual((content as? ViewElement)?.type, "Text", "Content should be Text")
        XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
        XCTAssertEqual((element.properties["values"] as? [Any])?.count, 3, "Values should have 3 elements")
        XCTAssertEqual(element.properties["trigger"] as? String, "onAppear", "Trigger should be onAppear")
        if let animation = animation {
            XCTAssertEqual(animation["type"] as? String, "spring", "Animation type should be spring")
            XCTAssertEqual(animation.cgFloat(forKey: "response"), 0.5, "Animation response should be 0.5")
            XCTAssertEqual(animation.cgFloat(forKey: "dampingFraction"), 0.7, "Animation dampingFraction should be 0.7")
        } else {
            XCTFail("Animation should be a dictionary")
        }
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        if state.wrappedValue[element.id] == nil {
            logger.log("Warning: State for id \(element.id) is nil", .warning)
        } else if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            logger.log("State dictionary: \(stateDict)", .debug)
        } else {
            XCTFail("State should be a dictionary or nil")
        }
    }
    
    func testPhaseAnimatorMalformedContent() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "PhaseAnimator",
            "content": ["id": 2, "properties": ["text": "Animating"]], // Missing type
            "properties": [
                "values": [0.0, 1.0]
            ]
        ]
        
        do {
            // Expecting failure, use ConsoleLogger to avoid test failure
            let consoleLogger = ConsoleLogger()
            let element = try ViewElement(from: elementDict, logger: consoleLogger)
            let _ = PhaseAnimator.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
