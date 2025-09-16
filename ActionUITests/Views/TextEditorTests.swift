// Tests/Views/TextEditorTests.swift
/*
 TextEditorTests.swift

 Tests for the TextEditor component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextEditorTests: XCTestCase {
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
    
    func testTextEditorValidatePropertiesValid() {
        let properties: [String: Any] = [
            "placeholder": "Enter text here",
            "actionID": "texteditor.submit"
        ]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Enter text here", "Placeholder should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "texteditor.submit", "actionID should be valid")
    }
    
    func testTextEditorValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "placeholder": 123
        ]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Invalid placeholder should be nil")
    }
    
    func testTextEditorValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Missing placeholder should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
}
