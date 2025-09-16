// Tests/Views/ToggleTests.swift
/*
 ToggleTests.swift

 Tests for the Toggle component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and platform-specific style application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToggleTests: XCTestCase {
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
    
    func testToggleValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "switch",
            "actionID": "toggle.submit"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Enable Feature", "Title should be valid")
        XCTAssertEqual(validated["style"] as? String, "switch", "Style should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "toggle.submit", "actionID should be valid")
    }
    
    func testToggleValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "style": "invalidStyle"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? Int, 123, "Invalid title should remain unchanged for baseline validation")
        XCTAssertNil(validated["style"], "Invalid style should be nil")
    }
    
    func testToggleValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
        XCTAssertNil(validated["style"], "Missing style should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    #if os(macOS)
    func testToggleValidatePropertiesMacOSCheckbox() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "checkbox"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["style"] as? String, "checkbox", "Checkbox style should be valid on macOS")
    }
    #else
    func testToggleValidatePropertiesNonMacOSCheckbox() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "checkbox"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertNil(validated["style"], "Checkbox style should be invalid on non-macOS platforms")
    }
    #endif
}
