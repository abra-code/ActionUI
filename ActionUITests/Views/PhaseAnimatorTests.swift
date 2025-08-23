// Tests/Views/PhaseAnimatorTests.swift
/*
 PhaseAnimatorTests.swift

 Tests for the PhaseAnimator component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for PhaseAnimator:
 {
   "type": "PhaseAnimator",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by StaticElement.init(from:).
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
    
    func testPhaseAnimatorJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "PhaseAnimator",
            "content": ["type": "Text", "id": 2, "properties": ["text": "Animating"]],
            "properties": [
                "values": [0.0, 1.0, 2.0],
                "trigger": "onAppear",
                "animation": ["type": "spring", "response": 0.5, "dampingFraction": 0.7]
            ]
        ]
        
        do {
            let element = try StaticElement(from: elementDict)
            let _ = PhaseAnimator.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            logger.log("content: \((content as? StaticElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "PhaseAnimator", "Element type should be PhaseAnimator")
            XCTAssertEqual((content as? StaticElement)?.type, "Text", "Content should be Text")
            XCTAssertEqual((content as? StaticElement)?.id, 2, "Content ID should be 2")
            XCTAssertEqual((element.properties["values"] as? [Double])?.count, 3, "Values should have 3 elements")
            XCTAssertEqual((element.properties["trigger"] as? String), "onAppear", "Trigger should be onAppear")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
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
            let element = try StaticElement(from: elementDict)
            let _ = PhaseAnimator.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
