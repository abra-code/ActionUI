// ActionUITestAppTests.swift
import XCTest
@testable import ActionUITestApp
import ActionUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ActionUITestAppUITests: XCTestCase {
    var app: XCUIApplication!

    private var supportsMultipleWindows: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.supportsMultipleScenes
        #else
        return true // macOS supports multiple windows
        #endif
    }

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetAppState"]
        app.launch()
        // Add delay to allow SwiftUI window initialization
        Thread.sleep(forTimeInterval: 5) // Increased to 5 seconds
        // Ensure JSON Selector window is focused
        if supportsMultipleWindows {
            let jsonSelectorWindow = app.windows["JSON Selector"].firstMatch
            var retryCount = 0
            while !jsonSelectorWindow.waitForExistence(timeout: 5) && retryCount < 5 {
                app.activate()
                print("Retry \(retryCount + 1): App activated due to missing JSON Selector window")
                retryCount += 1
                Thread.sleep(forTimeInterval: 1)
            }
            if jsonSelectorWindow.exists {
                jsonSelectorWindow.tap()
                print("JSON Selector window found and tapped")
            } else {
                print("JSON Selector window not found after \(retryCount) retries")
            }
        }
        print("Initial UI hierarchy: \(app.debugDescription)")
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testJSONSelectionAndUIHierarchy(jsonFileName: String, expectedElements: [String: XCUIElementQuery]) {
        // Check if no JSON files message is displayed
        let noJSONText = app.staticTexts["no_json_files_text"]
        if noJSONText.exists {
            XCTFail("No JSON files found in the app bundle. Ensure '\(jsonFileName).json' is included in the test target’s 'Copy Bundle Resources' build phase. UI hierarchy: \(app.debugDescription)")
            return
        }

        // Verify JSONSelectorView is displayed
        let jsonList = app.descendants(matching: .any).element(matching: .any, identifier: "json_selector_list")
        XCTAssertTrue(jsonList.waitForExistence(timeout: 15), "Element with accessibilityIdentifier 'json_selector_list' should appear within 15 seconds. UI hierarchy: \(app.debugDescription)")

        // Find and tap the button/link for the specified JSON file
        let jsonButton = jsonList.buttons[jsonFileName]
        XCTAssertTrue(jsonButton.exists, "Button for JSON file '\(jsonFileName)' should exist in the element with accessibilityIdentifier 'json_selector_list'. UI hierarchy: \(app.debugDescription)")
        jsonButton.tap()

        // Wait for the first expected UI element to appear
        let contentLoadTimeout: TimeInterval = 15
        guard let firstElement = expectedElements.first else {
            XCTFail("No expected elements provided for '\(jsonFileName)'")
            return
        }
        let element = firstElement.value[firstElement.key]
        if supportsMultipleWindows {
            XCTAssertTrue(
                app.windows.element(matching: .window, identifier: "ActionUITestApp.\(jsonFileName)-*").waitForExistence(timeout: contentLoadTimeout) || element.waitForExistence(timeout: contentLoadTimeout),
                "Window or element with accessibilityIdentifier '\(firstElement.key)' for '\(jsonFileName)' should load within \(contentLoadTimeout) seconds (multi-window). UI hierarchy: \(app.debugDescription)"
            )
        } else {
            XCTAssertTrue(
                element.waitForExistence(timeout: contentLoadTimeout),
                "Element with accessibilityIdentifier '\(firstElement.key)' for '\(jsonFileName)' should load within \(contentLoadTimeout) seconds (single-window navigation). UI hierarchy: \(app.debugDescription)"
            )
        }

        // Verify all expected UI elements
        for (accessibilityIdentifier, query) in expectedElements {
            let element = query[accessibilityIdentifier]
            XCTAssertTrue(element.exists, "Element with accessibilityIdentifier '\(accessibilityIdentifier)' should exist")
            XCTAssertTrue(element.isHittable, "Element with accessibilityIdentifier '\(accessibilityIdentifier)' should be hittable")
        }
    }

    func testHelloWorldUIHierarchy() {
        let expectedElements: [String: XCUIElementQuery] = [
            "globe_image": app.images,
            "hello_text": app.staticTexts
        ]
        testJSONSelectionAndUIHierarchy(jsonFileName: "HelloWorld", expectedElements: expectedElements)
    }

    func testButtonUIHierarchy() {
        let expectedElements: [String: XCUIElementQuery] = [
            "buttons_container": app.otherElements,
            "click_me_button": app.buttons,
            "submit_button": app.buttons,
            "delete_button": app.buttons,
            "disabled_button": app.buttons,
            "cancel_button": app.buttons
        ]
        testJSONSelectionAndUIHierarchy(jsonFileName: "Button", expectedElements: expectedElements)
    }

    func testImageUIHierarchy() {
        let expectedElements: [String: XCUIElementQuery] = [
            "images_grid": app.otherElements,
            "abracode_image": app.images,
            "star_image": app.images,
            "heart_image": app.images,
            "cloud_image": app.images,
            "photo_image": app.images
        ]
        testJSONSelectionAndUIHierarchy(jsonFileName: "Image", expectedElements: expectedElements)
    }
}
