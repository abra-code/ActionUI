//
//  ActionUITestAppTests.swift
//  ActionUITestAppTests
//

import XCTest
@testable import ActionUITestApp
import ActionUI

@MainActor
final class ActionUITestAppUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testContentViewUIHierarchy() {
        // Verify Image with accessibility identifier
        XCTAssertTrue(app.images["globe_image"].exists, "Image with accessibilityIdentifier 'globe_image' should exist")
        
        // Verify Text with accessibility identifier
        XCTAssertTrue(app.staticTexts["hello_text"].exists, "Text with accessibilityIdentifier 'hello_text' should exist")
        
        // Verify VStack layout (indirectly via existence and interaction)
        let textElement = app.staticTexts["hello_text"]
        XCTAssertTrue(textElement.isHittable, "Text element should be hittable, indicating proper VStack layout")
    }
}
