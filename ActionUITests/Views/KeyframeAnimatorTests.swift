// Tests/Views/KeyframeAnimatorTests.swift
/*
 KeyframeAnimatorTests.swift

 Tests for the KeyframeAnimator component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.

 Sample JSON for KeyframeAnimator:
 {
   "type": "KeyframeAnimator",
   "id": 1,
   "content": {
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
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
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
    
    func testKeyframeAnimatorJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "KeyframeAnimator",
            "content": {"type": "Text", "id": 2, "properties": {"text": "Animating"}},
            "properties": {
                "initialValue": {"opacity": 0.0, "scale": 1.0, "rotation": 0.0},
                "trigger": "onAppear",
                "keyframes": {
                    "0%": {"type": "linear", "value": {"opacity": 0.0, "scale": 0.5}, "duration": 0.8}
                }
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
        
        let _ = KeyframeAnimator.validateProperties(element.properties, logger)
        let content = element.subviews?["content"] as? any ActionUIElementBase
        logger.log("Validated content: \((content as? ActionUIElement)?.type ?? "nil")", .debug)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "KeyframeAnimator", "Element type should be KeyframeAnimator")
        XCTAssertEqual((content as? ActionUIElement)?.type, "Text", "Content should be Text")
        XCTAssertEqual((content as? ActionUIElement)?.id, 2, "Content ID should be 2")
        if let initialValue = element.properties["initialValue"] as? [String: Any] {
            XCTAssertEqual(initialValue.double(forKey: "opacity"), 0.0, "Initial opacity should be 0.0")
            XCTAssertEqual(initialValue.double(forKey: "scale"), 1.0, "Initial scale should be 1.0")
            XCTAssertEqual(initialValue.double(forKey: "rotation"), 0.0, "Initial rotation should be 0.0")
        } else {
            XCTFail("initialValue should be valid dictionary")
        }
        XCTAssertEqual(element.properties["trigger"] as? String, "onAppear", "Trigger should be onAppear")
        if let keyframes = element.properties["keyframes"] as? [String: [String: Any]], let keyframe = keyframes["0%"] {
            XCTAssertEqual(keyframe["type"] as? String, "linear", "Keyframe type should be linear")
            if let value = keyframe["value"] as? [String: Any] {
                XCTAssertEqual(value.double(forKey: "opacity"), 0.0, "Keyframe opacity should be 0.0")
                XCTAssertEqual(value.double(forKey: "scale"), 0.5, "Keyframe scale should be 0.5")
            } else {
                XCTFail("Keyframe value should be valid dictionary")
            }
            XCTAssertEqual(keyframe.double(forKey: "duration"), 0.8, "Keyframe duration should be 0.8")
        } else {
            XCTFail("keyframes should be valid dictionary")
        }
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
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
            // expecting failure, use ConsoleLogger instead of XCTestLogger
            let consoleLogger = ConsoleLogger()
            let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
            let _ = KeyframeAnimator.validateProperties(element.properties, logger)
            let content = element.subviews?["content"] as? any ActionUIElementBase
            XCTAssertNil(content as? ActionUIElement, "Malformed content should be nil")
        } catch {
            XCTFail("Failed to parse element: \(error)")
        }
    }
}
