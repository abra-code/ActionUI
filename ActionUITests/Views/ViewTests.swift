// Tests/Views/ViewTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ViewTests: XCTestCase {
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
    
    func testValidatePropertiesValid() throws {
        let properties: [String: Any] = [
            "padding": 10.0,
            "hidden": false,
            "foregroundColor": "blue",
            "font": "body",
            "background": "#FFFFFF",
            "frame": ["width": 100.0, "height": 100.0, "alignment": "center"],
            "offset": ["x": 10.0, "y": -5.0],
            "opacity": 0.5,
            "cornerRadius": 5.0,
            "actionID": "view.action",
            "disabled": true,
            "accessibilityLabel": "Test View",
            "accessibilityHint": "Base view",
            "accessibilityHidden": false,
            "accessibilityIdentifier": "view_1",
            "shadow": ["color": "black", "radius": 5.0, "x": 0.0, "y": 2.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be valid CGFloat")
        XCTAssertEqual(validated["hidden"] as? Bool, false, "hidden should be valid Bool")
        XCTAssertEqual(validated["foregroundColor"] as? String, "blue", "foregroundColor should be valid string")
        XCTAssertEqual(validated["font"] as? String, "body", "font should be valid string")
        XCTAssertEqual(validated["background"] as? String, "#FFFFFF", "background should be valid string")
        if let frame = validated["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "frame.width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 100.0, "frame.height should be 100.0")
            XCTAssertEqual(frame["alignment"] as? String, "center", "frame.alignment should be center")
        } else {
            XCTFail("frame should be a dictionary")
        }
        if let offset = validated["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 10.0, "offset.x should be 10.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        XCTAssertEqual(validated.cgFloat(forKey: "opacity"), 0.5, "opacity should be 0.5")
        XCTAssertEqual(validated.cgFloat(forKey: "cornerRadius"), 5.0, "cornerRadius should be 5.0")
        XCTAssertEqual(validated["actionID"] as? String, "view.action", "actionID should be view.action")
        XCTAssertEqual(validated["disabled"] as? Bool, true, "disabled should be true")
        XCTAssertEqual(validated["accessibilityLabel"] as? String, "Test View", "accessibilityLabel should be Test View")
        XCTAssertEqual(validated["accessibilityHint"] as? String, "Base view", "accessibilityHint should be Base view")
        XCTAssertEqual(validated["accessibilityHidden"] as? Bool, false, "accessibilityHidden should be false")
        XCTAssertEqual(validated["accessibilityIdentifier"] as? String, "view_1", "accessibilityIdentifier should be view_1")
        if let shadow = validated["shadow"] as? [String: Any] {
            XCTAssertEqual(shadow["color"] as? String, "black", "shadow.color should be black")
            XCTAssertEqual(shadow.cgFloat(forKey: "radius"), 5.0, "shadow.radius should be 5.0")
            XCTAssertEqual(shadow.cgFloat(forKey: "x"), 0.0, "shadow.x should be 0.0")
            XCTAssertEqual(shadow.cgFloat(forKey: "y"), 2.0, "shadow.y should be 2.0")
        } else {
            XCTFail("shadow should be a dictionary")
        }
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "padding": "10",
            "hidden": "true",
            "foregroundColor": 123,
            "font": 456,
            "background": 789,
            "frame": ["width": "100", "height": true],
            "offset": ["x": "10", "y": true],
            "opacity": "0.5",
            "cornerRadius": "5.0",
            "actionID": 999,
            "disabled": "false",
            "accessibilityLabel": 123,
            "accessibilityHint": 456,
            "accessibilityHidden": "true",
            "accessibilityIdentifier": 789,
            "shadow": ["color": 123, "radius": "5", "x": "0", "y": true]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["padding"], "padding should be nil for invalid type")
        XCTAssertNil(validated["hidden"], "hidden should be nil for invalid type")
        XCTAssertNil(validated["foregroundColor"], "foregroundColor should be nil for invalid type")
        XCTAssertNil(validated["font"], "font should be nil for invalid type")
        XCTAssertNil(validated["background"], "background should be nil for invalid type")
        XCTAssertNil(validated["frame"], "frame should be nil for invalid types")
        XCTAssertNil(validated["offset"], "offset should be nil for invalid types")
        XCTAssertNil(validated["opacity"], "opacity should be nil for invalid type")
        XCTAssertNil(validated["cornerRadius"], "cornerRadius should be nil for invalid type")
        XCTAssertNil(validated["actionID"], "actionID should be nil for invalid type")
        XCTAssertNil(validated["disabled"], "disabled should be nil for invalid type")
        XCTAssertNil(validated["accessibilityLabel"], "accessibilityLabel should be nil for invalid type")
        XCTAssertNil(validated["accessibilityHint"], "accessibilityHint should be nil for invalid type")
        XCTAssertNil(validated["accessibilityHidden"], "accessibilityHidden should be nil for invalid type")
        XCTAssertNil(validated["accessibilityIdentifier"], "accessibilityIdentifier should be nil for invalid type")
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid types")
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
            "offset": ["x": 15.0, "y": 25.0],
            "disabled": false,
            "accessibilityLabel": "Test View",
            "accessibilityIdentifier": "view_1"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 20.0, "padding should be valid CGFloat")
        XCTAssertEqual(validated["foregroundColor"] as? String, "red", "foregroundColor should be valid string")
        if let offset = validated["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be valid CGFloat")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), 25.0, "offset.y should be valid CGFloat")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        XCTAssertEqual(validated["disabled"] as? Bool, false, "disabled should be valid Bool")
        XCTAssertEqual(validated["accessibilityLabel"] as? String, "Test View", "accessibilityLabel should be valid string")
        XCTAssertEqual(validated["accessibilityIdentifier"] as? String, "view_1", "accessibilityIdentifier should be valid string")
        XCTAssertNil(validated["hidden"], "hidden should be nil when not provided")
        XCTAssertNil(validated["font"], "font should be nil when not provided")
        XCTAssertNil(validated["background"], "background should be nil when not provided")
        XCTAssertNil(validated["frame"], "frame should be nil when not provided")
        XCTAssertNil(validated["opacity"], "opacity should be nil when not provided")
        XCTAssertNil(validated["cornerRadius"], "cornerRadius should be nil when not provided")
        XCTAssertNil(validated["actionID"], "actionID should be nil when not provided")
        XCTAssertNil(validated["accessibilityHint"], "accessibilityHint should be nil when not provided")
        XCTAssertNil(validated["accessibilityHidden"], "accessibilityHidden should be nil when not provided")
        XCTAssertNil(validated["shadow"], "shadow should be nil when not provided")
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
        
        XCTAssertNil(validated["frame"], "frame should be nil if width is not a CGFloat")
    }
    
    func testValidatePropertiesFrameInvalidHeight() throws {
        let properties: [String: Any] = [
            "frame": ["width": 100.0, "height": "100"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil if height is not a CGFloat")
    }
    
    func testValidatePropertiesShadowPartial() throws {
        let properties: [String: Any] = [
            "shadow": ["color": "black", "radius": 5.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shadow = validated["shadow"] as? [String: Any] {
            XCTAssertEqual(shadow["color"] as? String, "black", "shadow.color should be valid string")
            XCTAssertEqual(shadow.cgFloat(forKey: "radius"), 5.0, "shadow.radius should be valid CGFloat")
            XCTAssertNil(shadow["x"], "shadow.x should be nil when not provided")
            XCTAssertNil(shadow["y"], "shadow.y should be nil when not provided")
        } else {
            XCTFail("shadow should be valid dictionary with partial properties")
        }
    }
    
    func testValidatePropertiesShadowInvalid() throws {
        let properties: [String: Any] = [
            "shadow": ["color": 123, "radius": "5", "x": "0", "y": true]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid types")
    }
    
    func testValidatePropertiesInvalidWithOtherValidProperties() throws {
        let properties: [String: Any] = [
            "frame": ["width": "100", "height": true],
            "offset": ["x": "10", "y": true],
            "shadow": ["color": 123, "radius": "5"],
            "padding": 20.0,
            "foregroundColor": "red",
            "opacity": 0.5,
            "disabled": false,
            "accessibilityLabel": "Test View",
            "accessibilityIdentifier": "view_1"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil for invalid types")
        XCTAssertNil(validated["offset"], "offset should be nil for invalid types")
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid types")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 20.0, "padding should be valid CGFloat")
        XCTAssertEqual(validated["foregroundColor"] as? String, "red", "foregroundColor should be valid string")
        XCTAssertEqual(validated.cgFloat(forKey: "opacity"), 0.5, "opacity should be valid CGFloat")
        XCTAssertEqual(validated["disabled"] as? Bool, false, "disabled should be valid Bool")
        XCTAssertEqual(validated["accessibilityLabel"] as? String, "Test View", "accessibilityLabel should be valid string")
        XCTAssertEqual(validated["accessibilityIdentifier"] as? String, "view_1", "accessibilityIdentifier should be valid string")
    }
    
    func testBuildViewAndApplyModifiers() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "padding": 10.0,
                "foregroundColor": "blue",
                "frame": {"width": 100.0, "height": 100.0, "alignment": "center"},
                "offset": {"x": 10.0, "y": -5.0},
                "accessibilityLabel": "Test View",
                "accessibilityHint": "Base view",
                "accessibilityHidden": false,
                "accessibilityIdentifier": "view_1",
                "shadow": {"color": "black", "radius": 5.0, "x": 0.0, "y": 2.0}
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
            XCTFail("Failed to retrive viewModel")
            return
        }

        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let modifiedView = View.applyModifiers(view, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to SwiftUI modifier wrapping")
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "frame.width should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "height"), 100.0, "frame.height should be 100.0")
            XCTAssertEqual(frame["alignment"] as? String, "center", "frame.alignment should be center")
        } else {
            XCTFail("frame should be a dictionary")
        }
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 10.0, "offset.x should be 10.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        if let shadow = element.properties["shadow"] as? [String: Any] {
            XCTAssertEqual(shadow["color"] as? String, "black", "shadow.color should be black")
            XCTAssertEqual(shadow.cgFloat(forKey: "radius"), 5.0, "shadow.radius should be 5.0")
            XCTAssertEqual(shadow.cgFloat(forKey: "x"), 0.0, "shadow.x should be 0.0")
            XCTAssertEqual(shadow.cgFloat(forKey: "y"), 2.0, "shadow.y should be 2.0")
        } else {
            XCTFail("shadow should be a dictionary")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        XCTAssertEqual(element.properties["foregroundColor"] as? String, "blue", "foregroundColor should be blue")
        XCTAssertEqual(element.properties["accessibilityLabel"] as? String, "Test View", "accessibilityLabel should be Test View")
        XCTAssertEqual(element.properties["accessibilityHint"] as? String, "Base view", "accessibilityHint should be Base view")
        XCTAssertEqual(element.properties["accessibilityHidden"] as? Bool, false, "accessibilityHidden should be false")
        XCTAssertEqual(element.properties["accessibilityIdentifier"] as? String, "view_1", "accessibilityIdentifier should be view_1")
    }
    
    func testBuildViewAndApplyModifiersEmptyProperties() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {}
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
            XCTFail("Failed to retrive viewModel")
            return
        }

        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView with empty properties")
    }
    
    func testValidatePropertiesOffsetPartial() throws {
        let properties: [String: Any] = [
            "offset": ["x": 10.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let offset = validated["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 10.0, "offset.x should be valid CGFloat")
            XCTAssertNil(offset["y"], "offset.y should be nil when not provided")
        } else {
            XCTFail("offset should be valid dictionary with partial properties")
        }
    }
    
    func testValidatePropertiesOffsetInvalidX() throws {
        let properties: [String: Any] = [
            "offset": ["x": "10", "y": 20.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["offset"], "offset should be nil if x is not a CGFloat")
    }
    
    func testValidatePropertiesOffsetInvalidY() throws {
        let properties: [String: Any] = [
            "offset": ["x": 10.0, "y": "20"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["offset"], "offset should be nil if y is not a CGFloat")
    }
    
    func testValidatePropertiesOffsetInvalidType() throws {
        let properties: [String: Any] = [
            "offset": "invalid"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["offset"], "offset should be nil for invalid type")
    }
    
    func testBuildViewAndApplyModifiersWithOffset() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "offset": {"x": 15.0, "y": -10.0},
                "padding": 10.0
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
            XCTFail("Failed to retrive viewModel")
            return
        }

        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let modifiedView = View.applyModifiers(view, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to offset and padding modifiers")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -10.0, "offset.y should be -10.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
    }
    
/* no XCUIApplication yet
    func testAccessibilityIdentifier() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "View",
            "properties": [
                "accessibilityIdentifier": "view_1"
            ]
        ]
        let element = try ViewElement(from: elementDict, logger: logger)
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, validatedProperties, logger)
        
        // Use XCUITest to verify accessibility identifier
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["view_1"].exists, "View with accessibilityIdentifier 'view_1' should exist")
    }
*/
}
