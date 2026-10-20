// Tests/Views/ProgressViewTests.swift
/*
 ProgressViewTests.swift

 Tests for the ProgressView component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ProgressViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testProgressViewPropsValid() {
        let properties: [String: Any] = [
            "value": 0.5,
            "total": 1.0,
            "title": "Loading",
            "actionID": "progress.tap"
        ]
        
        let props = ProgressView.Props(properties)
        
        XCTAssertEqual(props.value, 0.5, "value should be valid")
        XCTAssertEqual(props.total, 1.0, "total should be valid")
        XCTAssertEqual(props.title, "Loading", "title should be valid")
        XCTAssertEqual(props.actionID, "progress.tap", "actionID should be valid")
    }
    
    func testProgressViewPropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "value": -0.5,
            "total": 0.0,
            "title": 123
        ]
        
        let props = ProgressView.Props(properties)
        
        XCTAssertNil(props.value, "Invalid value should be nil")
        XCTAssertNil(props.total, "Invalid total should be nil")
        XCTAssertNil(props.title, "Invalid title should be nil")
    }
    
    func testProgressViewPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = ProgressView.Props(properties)
        
        XCTAssertNil(props.value, "Missing value should be nil")
        XCTAssertNil(props.total, "Missing total should be nil")
        XCTAssertNil(props.title, "Missing title should be nil")
        XCTAssertNil(props.actionID, "Missing actionID should be nil")
    }
    
    func testProgressViewPropsProgressViewStyle() {
        let expected: [(String, ActionUI.ProgressView.Props.Style)] = [("automatic", .automatic), ("linear", .linear), ("circular", .circular)]
        for (name, style) in expected {
            let props = ProgressView.Props(["progressViewStyle": name])
            XCTAssertEqual(props.style, style,
                           "\(name) should be read as a style")
        }
    }

    func testProgressViewPropsProgressViewStyleInvalid() {
        // A misspelling and a non-String. Both are ignored rather than passed
        // through, so applyModifiers' switch only ever sees a value it knows.
        let misspelled = ProgressView.Props(["progressViewStyle": "bar"])
        XCTAssertNil(misspelled.style, "An unknown style should be nil")

        let wrongType = ProgressView.Props(["progressViewStyle": 3])
        XCTAssertNil(wrongType.style, "A non-String style should be nil")
    }

    func testProgressViewConstructionLinearIndeterminate() throws {
        // The case the property exists for: no value, so the progress is
        // indeterminate, and "linear" asks for the animated bar rather than the
        // spinner macOS would otherwise resolve to. The rendering itself is not
        // observable from here - what is pinned is that the style is read
        // and the view builds with it applied.
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ProgressView",
            "properties": [
                "progressViewStyle": "linear"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let props = ProgressView.Props(properties)
        XCTAssertEqual(props.style, .linear,
                       "style should be read")
        XCTAssertNil(props.value, "no value: the progress is indeterminate")

        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
    }

    func testProgressViewConstructionCircularDeterminate() throws {
        // The mirror image: a value IS supplied, and "circular" asks for the
        // circular gauge rather than the bar the platform would default to.
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ProgressView",
            "properties": [
                "value": 0.25,
                "total": 1.0,
                "progressViewStyle": "circular"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let props = ProgressView.Props(properties)
        XCTAssertEqual(props.style, .circular,
                       "style should be read")

        let viewModel = ViewModel()
        viewModel.seedProperties(element.properties)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertEqual(ProgressView.initialValue(viewModel) as? Double, 0.25,
                       "a style must not disturb the value")
    }

    func testProgressViewConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ProgressView",
            "properties": [
                "value": 0.5,
                "total": 1.0,
                "title": "Loading",
                "actionID": "progress.tap",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testProgressViewConstructionValueWithoutTotal() throws {
        // Regression: a value with no explicit total is determinate — total
        // defaults to 1.0 in buildView (matching the documented contract and the
        // Android/Web ports), rather than falling through to an indeterminate
        // spinner. Build the view to exercise that path and confirm the value is
        // seeded onto the viewModel.
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "ProgressView",
            "properties": [
                "value": 0.3
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let props = ProgressView.Props(properties)
        XCTAssertEqual(props.value, 0.3, "value should be read")
        XCTAssertNil(props.total, "total stays absent; it is defaulted in buildView, not in Props")

        let viewModel = ViewModel()
        viewModel.seedProperties(element.properties)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertEqual(ProgressView.initialValue(viewModel) as? Double, 0.3, "initialValue should resolve to the JSON value")
    }

    func testProgressViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "ProgressView",
            "properties": {
                "value": 0.5,
                "total": 1.0,
                "title": "Loading",
                "actionID": "progress.tap",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
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
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "ProgressView", "Element type should be ProgressView")
        XCTAssertEqual(element.properties.double(forKey: "value"), 0.5, "value should be 0.5")
        XCTAssertEqual(element.properties.double(forKey: "total"), 1.0, "total should be 1.0")
        XCTAssertEqual(element.properties["title"] as? String, "Loading", "title should be Loading")
        XCTAssertEqual(element.properties["actionID"] as? String, "progress.tap", "actionID should be progress.tap")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? Double, 0.5, "Initial viewModel value should be 0.5")
    }
}
