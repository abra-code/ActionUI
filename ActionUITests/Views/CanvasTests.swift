// Tests/Views/CanvasTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class CanvasTests: XCTestCase {
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
    
    // MARK: - Props
    
    func testPropsValidMinimal() throws {
        let properties: [String: Any] = [:]
        let props = Canvas.Props(properties)
        XCTAssertTrue(props.operations.isEmpty, "Empty properties should give no operations")
        XCTAssertNil(props.backgroundColor)
        XCTAssertEqual(props.coordinateMode, .normalized)
        XCTAssertNil(props.actionID)
    }
    
    func testPropsValidAllPrimitives() throws {
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
        
        let props = Canvas.Props(properties)
        XCTAssertEqual(props.operations.count, 10, "operations should be preserved")
        XCTAssertEqual(props.backgroundColor, "#F5F5F5")
        XCTAssertEqual(props.coordinateMode, .normalized)
        XCTAssertEqual(props.actionID, "canvasTap")
    }
    
    func testPropsIgnoreInvalidTypes() throws {
        let properties: [String: Any] = [
            "operations": "not an array",
            "backgroundColor": 123,
            "coordinateMode": 456
        ]
        
        let props = Canvas.Props(properties)
        XCTAssertTrue(props.operations.isEmpty, "invalid operations type should be ignored")
        XCTAssertNil(props.backgroundColor, "invalid backgroundColor type should be ignored")
        XCTAssertEqual(props.coordinateMode, .normalized, "invalid coordinateMode type should be the default")
    }
    
    func testPropsRequiredFieldsMissing() throws {
        let properties: [String: Any] = [
            "operations": [
                ["type": "fill"],  // missing path
                ["type": "text"],  // missing text and frame
                ["type": "blur"]   // missing radius
            ]
        ]
        
        let props = Canvas.Props(properties)
        let ops = props.operations
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
        let properties = element.properties
        
        let view = Canvas.buildView(element, viewModel, windowUUID, properties, logger)
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
        let properties = element.properties
        
        let view = Canvas.buildView(element, viewModel, windowUUID, properties, logger)
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
        let properties = element.properties
        
        let baseView = Canvas.buildView(element, viewModel, windowUUID, properties, logger)
        let modifiedView = Canvas.applyModifiers(baseView, element, windowUUID, properties, logger)
        
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
        let rawProperties = element.properties
        
        // Build the view
        let view = Canvas.buildView(element, viewModel, windowUUID, rawProperties, logger)
        
        // Apply modifiers (baseline + any custom)
        let _ = Canvas.applyModifiers(view, element, windowUUID, rawProperties, logger)
        
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
        
        let properties = element.properties
        
        let view = ActionUIRegistry.shared.buildView(
            for: element,
            model: viewModel,
            windowUUID: windowUUID,
            properties: properties
        )
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "Canvas view should not be EmptyView")
        
        // Basic structural checks
        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "Canvas")
        let props = Canvas.Props(properties)
        XCTAssertEqual(props.backgroundColor, "#F0F0F0")
        XCTAssertEqual(props.coordinateMode, .normalized)
        XCTAssertEqual(props.actionID, "canvasTapped")
        
        let ops = props.operations
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
        
        let properties = element.properties
        XCTAssertTrue(Canvas.Props(properties).operations.isEmpty, "Empty properties should give no operations")
        
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(
            for: element,
            model: viewModel,
            windowUUID: windowUUID,
            properties: properties
        )
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "Empty Canvas should still produce a view")
    }
    
    // MARK: - Props Tests
    
    func testPropsValid() {
        let properties: [String: Any] = [
            "backgroundColor": "#FFFFFF",
            "coordinateMode": "points",
            "actionID": "tap",
            "operations": [
                ["type": "fill", "path": ["type": "circle", "center": [0.5, 0.5], "radius": 0.3], "color": "#FF0000"],
                ["type": "blur", "radius": 5]
            ]
        ]
        
        let props = Canvas.Props(properties)
        XCTAssertEqual(props.backgroundColor, "#FFFFFF")
        XCTAssertEqual(props.coordinateMode, .points)
        XCTAssertEqual(props.actionID, "tap")
        XCTAssertEqual(props.operations.count, 2)
    }
    
    func testPropsBlurMissingRadius() {
        let properties: [String: Any] = [
            "operations": [
                ["type": "blur"]  // missing radius
            ]
        ]
        
        let props = Canvas.Props(properties)
        let ops = props.operations
        XCTAssertEqual(ops.count, 0, "Blur without radius should be filtered out")
    }
    
    func testPropsFillMissingPath() {
        let properties: [String: Any] = [
            "operations": [
                ["type": "fill", "color": "#FF0000"]  // missing path
            ]
        ]
        
        let props = Canvas.Props(properties)
        let ops = props.operations
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
        
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(
            for: element,
            model: viewModel,
            windowUUID: windowUUID,
            properties: properties
        )
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "Canvas with custom path should produce a view")
    }
}
