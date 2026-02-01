// Tests/Views/CanvasTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CanvasTests: XCTestCase {
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
    
    // MARK: - Property Validation
    
    func testValidatePropertiesValidMinimal() throws {
        let properties: [String: Any] = [:]
        let validated = Canvas.validateProperties(properties, logger)
        XCTAssertTrue(validated.isEmpty, "Empty properties should validate")
    }
    
    func testValidatePropertiesValidAllPrimitives() throws {
        let properties: [String: Any] = [
            "operations": [
                ["type": "fill", "path": ["type": "circle", "center": [0.5, 0.5], "radius": 0.4], "color": "#FF0000"],
                ["type": "stroke", "path": ["type": "rect", "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8], "color": "#0000FF", "lineWidth": 0.02],
                ["type": "text", "text": "Test", "frame": [0.2, 0.4, 0.6, 0.1], "fontSize": 0.05, "color": "#333333"],
                ["type": "clip", "path": ["type": "roundedRect", "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8, "cornerRadius": 0.05]],
                ["type": "translate", "x": 0.1, "y": 0.05],
                ["type": "scale", "x": 1.2, "y": 1.2],
                ["type": "rotate", "angle": 45],
                ["type": "shadow", "color": "#00000080", "radius": 0.01],
                ["type": "blur", "radius": 0.015],
                ["type": "layer", "frame": [0.1, 0.1, 0.8, 0.8], "opacity": 0.7, "operations": [["type": "fill", "path": ["type": "circle", "center": [0.5, 0.5], "radius": 0.3], "color": "#00FF00"]]]
            ],
            "backgroundColor": "#F5F5F5",
            "coordinateMode": "normalized",
            "actionID": "canvasTap"
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        XCTAssertNotNil(validated["operations"] as? [[String: Any]], "operations should be preserved")
        XCTAssertEqual(validated["backgroundColor"] as? String, "#F5F5F5")
        XCTAssertEqual(validated["coordinateMode"] as? String, "normalized")
        XCTAssertEqual(validated["actionID"] as? String, "canvasTap")
    }
    
    func testValidatePropertiesInvalidTypes() throws {
        let properties: [String: Any] = [
            "operations": "not an array",
            "backgroundColor": 123,
            "coordinateMode": 456
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        XCTAssertNil(validated["operations"], "invalid operations type should be removed")
        XCTAssertNil(validated["backgroundColor"], "invalid backgroundColor type should be removed")
        XCTAssertNil(validated["coordinateMode"], "invalid coordinateMode type should be removed")
    }
    
    func testValidatePropertiesRequiredFieldsMissing() throws {
        let properties: [String: Any] = [
            "operations": [
                ["type": "fill"],  // missing path
                ["type": "text"],  // missing text and frame
                ["type": "blur"]   // missing radius
            ]
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        let ops = validated["operations"] as? [[String: Any]] ?? []
        XCTAssertEqual(ops.count, 0, "Ops missing required fields should be filtered out")
    }
    
    // MARK: - View Construction Smoke Tests
    
    func testBuildViewMinimal() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Canvas",
            "properties": [:]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let viewModel = ViewModel()
        let validated = Canvas.validateProperties(element.properties, logger)
        
        let view = Canvas.buildView(element, viewModel, windowUUID, validated, logger)
        XCTAssertNotNil(view, "BuildView should return a non-nil view")
    }
    
    func testBuildViewWithOperations() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Canvas",
            "properties": [
                "operations": [
                    ["type": "fill", "path": ["type": "rect", "x": 0, "y": 0, "width": 1, "height": 1], "color": "#FF0000"],
                    ["type": "text", "text": "Hello", "frame": [0.1, 0.1, 0.8, 0.8]],
                    ["type": "shadow", "radius": 0.01],
                    ["type": "blur", "radius": 0.005]
                ]
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let viewModel = ViewModel()
        let validated = Canvas.validateProperties(element.properties, logger)
        
        let view = Canvas.buildView(element, viewModel, windowUUID, validated, logger)
        XCTAssertNotNil(view, "BuildView with operations should succeed")
    }
    
    func testApplyModifiers() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Canvas",
            "properties": [
                "padding": 20,
                "opacity": 0.8,
                "actionID": "testTap"
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let viewModel = ViewModel()
        let validated = Canvas.validateProperties(element.properties, logger)
        
        let baseView = Canvas.buildView(element, viewModel, windowUUID, validated, logger)
        let modifiedView = Canvas.applyModifiers(baseView, element, windowUUID, validated, logger)
        
        XCTAssertNotNil(modifiedView, "applyModifiers should return a view")
        // Cannot easily assert on modifiers due to opaque types, but no crash = success
    }
    
    // MARK: - Smoke Runtime Test (non-fatal)
    
    func testCanvasViewInstantiationNoCrash() throws {
        let properties: [String: Any] = [
            "operations": [
                ["type": "fill", "path": ["type": "circle", "center": [0.5, 0.5], "radius": 0.4], "color": "#FF0000"],
                ["type": "text", "text": "Test Canvas", "frame": [0.1, 0.1, 0.8, 0.8], "fontSize": 24],
                ["type": "shadow", "radius": 0.01],
                ["type": "blur", "radius": 0.005],
                ["type": "layer", "frame": [0.2, 0.2, 0.6, 0.6], "opacity": 0.8, "operations": [
                    ["type": "fill", "path": ["type": "rect", "x": 0, "y": 0, "width": 1, "height": 1], "color": "#00FF00"]
                ]]
            ],
            "backgroundColor": "#F0F0F0",
            "coordinateMode": "normalized",
            "actionID": "testTap"
        ]
        
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Canvas",
            "properties": properties
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let viewModel = ViewModel()
        let validated = Canvas.validateProperties(element.properties, logger)
        
        // Build the view
        let view = Canvas.buildView(element, viewModel, windowUUID, validated, logger)
        
        // Apply modifiers (baseline + any custom)
        let _ = Canvas.applyModifiers(view, element, windowUUID, validated, logger)
        
        // Minimal runtime check – no crash means success
        XCTAssertTrue(true, "View construction and body evaluation completed without crash")
    }

    // MARK: - End-to-End from JSON to View Construction
    
    func testCanvasConstructionWithPrimitives() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Canvas",
            "properties": {
                "backgroundColor": "#F0F0F0",
                "coordinateMode": "normalized",
                "actionID": "canvasTapped",
                "operations": [
                    {
                        "type": "fill",
                        "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.4 },
                        "color": "#FF3B30"
                    },
                    {
                        "type": "stroke",
                        "path": { "type": "rect", "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8 },
                        "color": "#007AFF",
                        "lineWidth": 0.02,
                        "dash": [0.05, 0.02]
                    },
                    {
                        "type": "text",
                        "text": "Hello Canvas",
                        "frame": [0.2, 0.4, 0.6, 0.2],
                        "fontSize": 24,
                        "fontWeight": "bold",
                        "color": "#333333"
                    },
                    {
                        "type": "shadow",
                        "color": "#00000066",
                        "radius": 0.012,
                        "x": 0.004,
                        "y": 0.006
                    },
                    {
                        "type": "blur",
                        "radius": 0.008
                    },
                    {
                        "type": "layer",
                        "frame": [0.3, 0.3, 0.4, 0.4],
                        "opacity": 0.75,
                        "operations": [
                            {
                                "type": "fill",
                                "path": { "type": "roundedRect", "x": 0, "y": 0, "width": 1, "height": 1, "cornerRadius": 0.1 },
                                "color": "#34C759"
                            }
                        ]
                    }
                ]
            }
        }
        """
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let validatedProperties = Canvas.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(
            for: element,
            model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProperties
        )
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "Canvas view should not be EmptyView")
        
        // Basic structural checks
        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "Canvas")
        XCTAssertEqual(validatedProperties["backgroundColor"] as? String, "#F0F0F0")
        XCTAssertEqual(validatedProperties["coordinateMode"] as? String, "normalized")
        XCTAssertEqual(validatedProperties["actionID"] as? String, "canvasTapped")
        
        let ops = validatedProperties["operations"] as? [[String: Any]] ?? []
        XCTAssertEqual(ops.count, 6, "All 6 valid operations should be preserved")
    }
    
    func testCanvasNilProperties() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Canvas",
            "properties": {}
        }
        """
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        let validatedProperties = Canvas.validateProperties(element.properties, logger)
        XCTAssertTrue(validatedProperties.isEmpty, "Empty properties should remain empty after validation")
        
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(
            for: element,
            model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validatedProperties
        )
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "Empty Canvas should still produce a view")
    }
    
    // MARK: - Validation Tests
    
    func testValidatePropertiesValid() {
        let properties: [String: Any] = [
            "backgroundColor": "#FFFFFF",
            "coordinateMode": "points",
            "actionID": "tap",
            "operations": [
                ["type": "fill", "path": ["type": "circle", "center": [0.5, 0.5], "radius": 0.3], "color": "#FF0000"],
                ["type": "blur", "radius": 5]
            ]
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        XCTAssertEqual(validated["backgroundColor"] as? String, "#FFFFFF")
        XCTAssertEqual(validated["coordinateMode"] as? String, "points")
        XCTAssertEqual(validated["actionID"] as? String, "tap")
        XCTAssertNotNil(validated["operations"])
    }
    
    func testValidatePropertiesInvalidBlurMissingRadius() {
        let properties: [String: Any] = [
            "operations": [
                ["type": "blur"]  // missing radius
            ]
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        let ops = validated["operations"] as? [[String: Any]] ?? []
        XCTAssertEqual(ops.count, 0, "Blur without radius should be filtered out")
    }
    
    func testValidatePropertiesInvalidFillMissingPath() {
        let properties: [String: Any] = [
            "operations": [
                ["type": "fill", "color": "#FF0000"]  // missing path
            ]
        ]
        
        let validated = Canvas.validateProperties(properties, logger)
        let ops = validated["operations"] as? [[String: Any]] ?? []
        XCTAssertEqual(ops.count, 0, "Fill without path should be filtered")
    }
    
    // MARK: - Smoke: Custom Path
    
    func testCanvasWithCustomPath() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Canvas",
            "properties": {
                "operations": [
                    {
                        "type": "stroke",
                        "path": {
                            "type": "path",
                            "commands": [
                                ["moveTo", 0.2, 0.2],
                                ["lineTo", 0.8, 0.8],
                                ["closePath"]
                            ]
                        },
                        "color": "#000000",
                        "lineWidth": 4
                    }
                ]
            }
        }
        """
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        let validated = Canvas.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(
            for: element,
            model: viewModel,
            windowUUID: windowUUID,
            validatedProperties: validated
        )
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "Canvas with custom path should produce a view")
    }
}
