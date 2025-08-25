// Tests/Views/KeyframeAnimatorTests.swift
/*
 KeyframeAnimatorTests.swift

 Tests for the KeyframeAnimator component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "content": {          // Note: Declared as a top-level key in JSON but stored in subviews["content"] by ViewElement.init(from:).
     "type": "Text", "properties": { "text": "Animating" }
   },
   "properties": {
     "initialValue": { "opacity": 0.0, "scale": 1.0, "rotation": 0.0 },
     "trigger": "onAppear",
     "keyframes": {
       "0%": { "type": "linear", "value": { "opacity": 0.0, "scale": 0.5 }, "duration": 0.8 }
     }
   }
 }
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class KeyframeAnimatorTests: XCTestCase {
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
    
    func testKeyframeAnimatorJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "KeyframeAnimator",
            "content": ["type": "Text", "id": 2, "properties": ["text": "Animating"]],
            "properties": [
                "initialValue": ["opacity": 0.0, "scale": 1.0, "rotation": 0.0],
                "trigger": "onAppear",
                "keyframes": [
                    "0%": ["type": "linear", "value": ["opacity": 0.0, "scale": 0.5], "duration": 0.8]
                ]
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = KeyframeAnimator.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            logger.log("Validated content: \((content as? ViewElement)?.type ?? "nil")", .debug)
            
            XCTAssertEqual(element.id, 1, "Element ID should be 1")
            XCTAssertEqual(element.type, "KeyframeAnimator", "Element type should be KeyframeAnimator")
            XCTAssertEqual((content as? ViewElement)?.type, "Text", "Content should be Text")
            XCTAssertEqual((content as? ViewElement)?.id, 2, "Content ID should be 2")
            XCTAssertEqual((element.properties["initialValue"] as? [String: Any])?["opacity"] as? Double, 0.0, "Initial opacity should be 0.0")
            XCTAssertEqual((element.properties["trigger"] as? String), "onAppear", "Trigger should be onAppear")
            XCTAssertEqual((element.properties["keyframes"] as? [String: [String: Any]])?["0%"]?["type"] as? String, "linear", "Keyframe type should be linear")
            XCTAssertNil(element.subviews?["children"], "Children should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
    
    func testKeyframeAnimatorMalformedContent() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "KeyframeAnimator",
            "content": ["id": 2, "properties": ["text": "Animating"]], // Missing type
            "properties": [
                "initialValue": ["opacity": 0.0, "scale": 1.0]
            ]
        ]
        
        do {
            let element = try ViewElement(from: elementDict, logger: logger)
            let _ = KeyframeAnimator.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElement
            XCTAssertNil(content as? ViewElement, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
