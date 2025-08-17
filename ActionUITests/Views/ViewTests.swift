// Tests/Views/ViewTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ViewTests: XCTestCase {
    private var logger: XCTestLogger!
    
    override func setUp() {
        super.setUp()
        // Initialize XCTestLogger with verbose level to catch errors
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        super.tearDown()
    }
    
    func testValidatePropertiesValid() throws {
        let properties: [String: Any] = [
            "padding": 10.0,
            "hidden": false,
            "foregroundColor": "blue",
            "font": "body",
            "background": "#FFFFFF",
            "frame": ["width": 100.0, "height": 100.0],
            "opacity": 0.5,
            "cornerRadius": 5.0,
            "actionID": "view.action",
            "disabled": true
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["padding"] as? Double, 10.0, "padding should be valid Double")
        XCTAssertEqual(validated["hidden"] as? Bool, false, "hidden should be valid Bool")
        XCTAssertEqual(validated["foregroundColor"] as? String, "blue", "foregroundColor should be valid string")
        XCTAssertEqual(validated["font"] as? String, "body", "font should be valid string")
        XCTAssertEqual(validated["background"] as? String, "#FFFFFF", "background should be valid string")
        if let frame = validated["frame"] as? [String: Any] {
            XCTAssertEqual(frame["width"] as? Double, 100.0, "frame.width should be valid Double")
            XCTAssertEqual(frame["height"] as? Double, 100.0, "frame.height should be valid Double")
        } else {
            XCTFail("frame should be valid dictionary")
        }
        XCTAssertEqual(validated["opacity"] as? Double, 0.5, "opacity should be valid Double")
        XCTAssertEqual(validated["cornerRadius"] as? Double, 5.0, "cornerRadius should be valid Double")
        XCTAssertEqual(validated["actionID"] as? String, "view.action", "actionID should be valid string")
        XCTAssertEqual(validated["disabled"] as? Bool, true, "disabled should be valid Bool")
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "padding": "10",
            "hidden": "true",
            "foregroundColor": 123,
            "font": 456,
            "background": 789,
            "frame": ["width": "100", "height": true],
            "opacity": "0.5",
            "cornerRadius": "5.0",
            "actionID": 999,
            "disabled": "false"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["padding"], "padding should be nil for invalid type")
        XCTAssertNil(validated["hidden"], "hidden should be nil for invalid type")
        XCTAssertNil(validated["foregroundColor"], "foregroundColor should be nil for invalid type")
        XCTAssertNil(validated["font"], "font should be nil for invalid type")
        XCTAssertNil(validated["background"], "background should be nil for invalid type")
        XCTAssertNil(validated["frame"], "frame should be nil for invalid types")
        XCTAssertNil(validated["opacity"], "opacity should be nil for invalid type")
        XCTAssertNil(validated["cornerRadius"], "cornerRadius should be nil for invalid type")
        XCTAssertNil(validated["actionID"], "actionID should be nil for invalid type")
        XCTAssertNil(validated["disabled"], "disabled should be nil for invalid type")
    }
    
    func testValidatePropertiesOutOfRangeOpacity() throws {
        let properties: [String: Any] = [
            "opacity": 1.5
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["opacity"], "opacity should be nil for out-of-range value")
    }
    
    func testValidatePropertiesMissing() throws {
        let properties: [String: Any] = [:]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "validated properties should be empty when no properties provided")
    }
    
    func testValidatePropertiesPartial() throws {
        let properties: [String: Any] = [
            "padding": 20.0,
            "foregroundColor": "red",
            "disabled": false
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["padding"] as? Double, 20.0, "padding should be valid Double")
        XCTAssertEqual(validated["foregroundColor"] as? String, "red", "foregroundColor should be valid string")
        XCTAssertEqual(validated["disabled"] as? Bool, false, "disabled should be valid Bool")
        XCTAssertNil(validated["hidden"], "hidden should be nil when not provided")
        XCTAssertNil(validated["font"], "font should be nil when not provided")
        XCTAssertNil(validated["background"], "background should be nil when not provided")
        XCTAssertNil(validated["frame"], "frame should be nil when not provided")
        XCTAssertNil(validated["opacity"], "opacity should be nil when not provided")
        XCTAssertNil(validated["cornerRadius"], "cornerRadius should be nil when not provided")
        XCTAssertNil(validated["actionID"], "actionID should be nil when not provided")
    }
    
    func testValidatePropertiesFramePartial() throws {
        let properties: [String: Any] = [
            "frame": ["width": 100.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil if height is missing")
    }
    
    func testValidatePropertiesFrameInvalidWidth() throws {
        let properties: [String: Any] = [
            "frame": ["width": "100", "height": 100.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil if width is not a Double")
    }
    
    func testValidatePropertiesFrameInvalidHeight() throws {
        let properties: [String: Any] = [
            "frame": ["width": 100.0, "height": "100"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil if height is not a Double")
    }
    
    func testValidatePropertiesInvalidFrameWithOtherValidProperties() throws {
        let properties: [String: Any] = [
            "frame": ["width": "100", "height": true],
            "padding": 20.0,
            "foregroundColor": "red",
            "opacity": 0.5,
            "disabled": false
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil for invalid types")
        XCTAssertEqual(validated["padding"] as? Double, 20.0, "padding should be valid Double")
        XCTAssertEqual(validated["foregroundColor"] as? String, "red", "foregroundColor should be valid string")
        XCTAssertEqual(validated["opacity"] as? Double, 0.5, "opacity should be valid Double")
        XCTAssertEqual(validated["disabled"] as? Bool, false, "disabled should be valid Bool")
    }
}
