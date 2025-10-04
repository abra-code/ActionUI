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
    
    func testValidatePropertiesValid() throws {
        let properties: [String: Any] = [
            "padding": 10.0,
            "hidden": false,
            "foregroundStyle": "blue",
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
        XCTAssertEqual(validated["foregroundStyle"] as? String, "blue", "foregroundStyle should be valid string")
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
    
    func testValidatePropertiesValidFlexibleFrame() throws {
        let properties: [String: Any] = [
            "frame": ["minWidth": 50.0, "idealWidth": 100.0, "maxWidth": 200.0, "minHeight": 50.0, "idealHeight": 100.0, "maxHeight": 200.0, "alignment": "topLeading"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let frame = validated["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "minWidth"), 50.0, "frame.minWidth should be 50.0")
            XCTAssertEqual(frame.cgFloat(forKey: "idealWidth"), 100.0, "frame.idealWidth should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "maxWidth"), 200.0, "frame.maxWidth should be 200.0")
            XCTAssertEqual(frame.cgFloat(forKey: "minHeight"), 50.0, "frame.minHeight should be 50.0")
            XCTAssertEqual(frame.cgFloat(forKey: "idealHeight"), 100.0, "frame.idealHeight should be 100.0")
            XCTAssertEqual(frame.cgFloat(forKey: "maxHeight"), 200.0, "frame.maxHeight should be 200.0")
            XCTAssertEqual(frame["alignment"] as? String, "topLeading", "frame.alignment should be topLeading")
        } else {
            XCTFail("frame should be a dictionary")
        }
    }
    
    func testValidatePropertiesInvalid() throws {
        let properties: [String: Any] = [
            "padding": "10",
            "hidden": "true",
            "foregroundStyle": 123,
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
        XCTAssertNil(validated["foregroundStyle"], "foregroundStyle should be nil for invalid type")
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
            "foregroundStyle": "red",
            "offset": ["x": 15.0, "y": 25.0],
            "disabled": false,
            "accessibilityLabel": "Test View",
            "accessibilityIdentifier": "view_1"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 20.0, "padding should be valid CGFloat")
        XCTAssertEqual(validated["foregroundStyle"] as? String, "red", "foregroundStyle should be valid string")
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
        
        if let frame = validated["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "width"), 100.0, "frame.width should be 100.0")
            XCTAssertNil(frame["height"], "frame.height should be nil when not provided")
            XCTAssertNil(frame["alignment"], "frame.alignment should be nil when not provided")
        } else {
            XCTFail("frame should be a dictionary")
        }
    }
    
    func testValidatePropertiesFrameMixedForms() throws {
        let properties: [String: Any] = [
            "frame": ["width": 100.0, "minWidth": 50.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil for mixed fixed and flexible keys")
    }
    
    func testValidatePropertiesFrameInvalidAlignment() throws {
        let properties: [String: Any] = [
            "frame": ["alignment": "invalid"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let frame = validated["frame"] as? [String: Any] {
            XCTAssertEqual(frame["alignment"] as? String, "invalid", "frame.alignment should retain invalid value")
        } else {
            XCTFail("frame should be a dictionary with only alignment")
        }
    }
    
    func testValidatePropertiesFrameInvalidTypes() throws {
        let properties: [String: Any] = [
            "frame": ["width": "100", "height": true]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["frame"], "frame should be nil for invalid dimension types")
    }
    
    func testValidatePropertiesShadowPartial() throws {
        let properties: [String: Any] = [
            "shadow": ["radius": 10.0, "x": 3.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shadow = validated["shadow"] as? [String: Any] {
            XCTAssertNil(shadow["color"], "shadow.color should be nil when not provided")
            XCTAssertEqual(shadow.cgFloat(forKey: "radius"), 10.0, "shadow.radius should be valid CGFloat")
            XCTAssertEqual(shadow.cgFloat(forKey: "x"), 3.0, "shadow.x should be valid CGFloat")
            XCTAssertNil(shadow["y"], "shadow.y should be nil when not provided")
        } else {
            XCTFail("shadow should be valid dictionary with partial properties")
        }
    }
    
    func testValidatePropertiesShadowInvalidTypes() throws {
        let properties: [String: Any] = [
            "shadow": ["color": 123, "radius": "10", "x": true, "y": "2"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid types")
    }
    
    func testValidatePropertiesShadowInvalidColorType() throws {
        let properties: [String: Any] = [
            "shadow": ["color": 123]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid color type")
    }
    
    func testValidatePropertiesShadowInvalidRadiusType() throws {
        let properties: [String: Any] = [
            "shadow": ["radius": "10"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid radius type")
    }
    
    func testValidatePropertiesShadowInvalidXType() throws {
        let properties: [String: Any] = [
            "shadow": ["x": true]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid x type")
    }
    
    func testValidatePropertiesShadowInvalidYType() throws {
        let properties: [String: Any] = [
            "shadow": ["y": "2"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid y type")
    }
    
    func testValidatePropertiesShadowEmptyDict() throws {
        let properties: [String: Any] = [
            "shadow": [:]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for empty dictionary")
    }
    
    func testValidatePropertiesShadowInvalidType() throws {
        let properties: [String: Any] = [
            "shadow": "invalid"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["shadow"], "shadow should be nil for invalid type")
    }
    
    func testValidatePropertiesPaddingDictPartial() throws {
        let properties: [String: Any] = [
            "padding": ["top": 10.0, "leading": 5.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let padding = validated["padding"] as? [String: Any] {
            XCTAssertEqual(padding.cgFloat(forKey: "top"), 10.0, "padding.top should be valid CGFloat")
            XCTAssertEqual(padding.cgFloat(forKey: "leading"), 5.0, "padding.leading should be valid CGFloat")
            XCTAssertNil(padding["bottom"], "padding.bottom should be nil when not provided")
            XCTAssertNil(padding["trailing"], "padding.trailing should be nil when not provided")
        } else {
            XCTFail("padding should be valid dictionary with partial properties")
        }
    }
    
    func testValidatePropertiesPaddingDictInvalidTypes() throws {
        let properties: [String: Any] = [
            "padding": ["top": "10", "bottom": true, "leading": "5", "trailing": 15.0]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let padding = validated["padding"] as? [String: Any] {
            XCTAssertEqual(padding.cgFloat(forKey: "trailing"), 15.0, "padding.trailing should be valid CGFloat")
            XCTAssertNil(padding["top"], "padding.top should be nil for invalid type")
            XCTAssertNil(padding["bottom"], "padding.bottom should be nil for invalid type")
            XCTAssertNil(padding["leading"], "padding.leading should be nil for invalid type")
        } else {
            XCTFail("padding should be a dictionary with valid edges")
        }
    }
    
    func testValidatePropertiesPaddingStringDefault() throws {
        let properties: [String: Any] = [
            "padding": "default"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["padding"] as? String, "default", "padding should be 'default' string")
    }
    
    func testValidatePropertiesPaddingStringInvalid() throws {
        let properties: [String: Any] = [
            "padding": "invalid"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["padding"], "padding should be nil for invalid string")
    }
    
    func testValidatePropertiesPaddingInvalidType() throws {
        let properties: [String: Any] = [
            "padding": true
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["padding"], "padding should be nil for invalid type")
    }
    
    func testValidatePropertiesOpacityInvalidValue() throws {
        let properties: [String: Any] = [
            "opacity": 1.5
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["opacity"], "opacity should be nil for value outside 0.0-1.0 range")
    }
    
    func testValidatePropertiesOpacityValidBoundary() throws {
        let properties: [String: Any] = [
            "opacity": 0.0
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "opacity"), 0.0, "opacity should be valid at 0.0")
    }
    
    func testValidatePropertiesOpacityValidOne() throws {
        let properties: [String: Any] = [
            "opacity": 1.0
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "opacity"), 1.0, "opacity should be valid at 1.0")
    }
    
    func testValidatePropertiesFrameAlignmentOnly() throws {
        let properties: [String: Any] = [
            "frame": ["alignment": "center"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let frame = validated["frame"] as? [String: Any] {
            XCTAssertEqual(frame["alignment"] as? String, "center", "frame.alignment should be center")
            XCTAssertNil(frame["width"], "frame.width should be nil when not provided")
        } else {
            XCTFail("frame should be a dictionary with only alignment")
        }
    }
    
    func testBuildViewAndApplyModifiers() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "padding": 10.0,
                "foregroundStyle": "blue",
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
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        //        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to SwiftUI modifier wrapping")
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
        XCTAssertEqual(element.properties["foregroundStyle"] as? String, "blue", "foregroundStyle should be blue")
        XCTAssertEqual(element.properties["accessibilityLabel"] as? String, "Test View", "accessibilityLabel should be Test View")
        XCTAssertEqual(element.properties["accessibilityHint"] as? String, "Base view", "accessibilityHint should be Base view")
        XCTAssertEqual(element.properties["accessibilityHidden"] as? Bool, false, "accessibilityHidden should be false")
        XCTAssertEqual(element.properties["accessibilityIdentifier"] as? String, "view_1", "accessibilityIdentifier should be view_1")
    }
    
    func testBuildViewAndApplyModifiersFlexibleFrame() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "frame": {"minWidth": 50.0, "idealHeight": 100.0, "alignment": "topLeading"}
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
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        //        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to flexible frame modifier")
        if let frame = element.properties["frame"] as? [String: Any] {
            XCTAssertEqual(frame.cgFloat(forKey: "minWidth"), 50.0, "frame.minWidth should be 50.0")
            XCTAssertEqual(frame.cgFloat(forKey: "idealHeight"), 100.0, "frame.idealHeight should be 100.0")
            XCTAssertEqual(frame["alignment"] as? String, "topLeading", "frame.alignment should be topLeading")
        } else {
            XCTFail("frame should be a dictionary")
        }
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
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
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
            XCTFail("Failed to retrieve viewModel")
            return
        }
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        //        XCTAssertFalse(modifiedView is SwiftUI.EmptyView, "applyModifiers returns a modified view due to offset and padding modifiers")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 15.0, "offset.x should be 15.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -10.0, "offset.y should be -10.0")
        } else {
            XCTFail("offset should be a dictionary")
        }
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
    }
    
    func testValidatePropertiesKeyboardShortcutValidSingleChar() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "a", "modifiers": ["command", "shift"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "a", "keyboardShortcut.key should be 'a'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["command", "shift"]), "keyboardShortcut.modifiers should be ['command', 'shift']")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testValidatePropertiesKeyboardShortcutValidSpecialKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "return", "modifiers": ["option"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "return", "keyboardShortcut.key should be 'return'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["option"]), "keyboardShortcut.modifiers should be ['option']")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testValidatePropertiesKeyboardShortcutDuplicateModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "b", "modifiers": ["command", "command", "shift"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "b", "keyboardShortcut.key should be 'b'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["command", "shift"]), "keyboardShortcut.modifiers should remove duplicates")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
        // Note: Check logger for warning about duplicates, but since XCTestLogger doesn't expose logs for assertion, assume it's logged
    }
    
    func testValidatePropertiesKeyboardShortcutInvalidModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "c", "modifiers": ["invalid1", "invalid2"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "c", "keyboardShortcut.key should be 'c'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(modifiers, ["command"], "keyboardShortcut.modifiers should default to ['command'] for invalid modifiers")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testValidatePropertiesKeyboardShortcutMissingModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "d"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "d", "keyboardShortcut.key should be 'd'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(modifiers, ["command"], "keyboardShortcut.modifiers should default to ['command'] when missing")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testValidatePropertiesKeyboardShortcutEmptyModifiers() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "e", "modifiers": []]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "e", "keyboardShortcut.key should be 'e'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(modifiers, ["command"], "keyboardShortcut.modifiers should default to ['command'] for empty array")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testValidatePropertiesKeyboardShortcutInvalidKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "invalid", "modifiers": ["command"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["keyboardShortcut"], "keyboardShortcut should be nil for invalid key")
    }
    
    func testValidatePropertiesKeyboardShortcutMultiCharKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "ab", "modifiers": ["command"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["keyboardShortcut"], "keyboardShortcut should be nil for multi-character key (non-special)")
    }
    
    func testValidatePropertiesKeyboardShortcutInvalidType() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": "invalid"
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["keyboardShortcut"], "keyboardShortcut should be nil for invalid type")
    }
    
    func testValidatePropertiesKeyboardShortcutMissingKey() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["modifiers": ["command"]]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        XCTAssertNil(validated["keyboardShortcut"], "keyboardShortcut should be nil for missing key")
    }
    
    func testValidatePropertiesKeyboardShortcutInvalidModifiersType() throws {
        let properties: [String: Any] = [
            "keyboardShortcut": ["key": "f", "modifiers": "command"]
        ]
        
        let validated = View.validateProperties(properties, logger)
        
        if let shortcut = validated["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "f", "keyboardShortcut.key should be 'f'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(modifiers, ["command"], "keyboardShortcut.modifiers should default to ['command'] for invalid type")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testBuildViewAndApplyModifiersWithKeyboardShortcut() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "keyboardShortcut": {"key": "s", "modifiers": ["command", "shift"]}
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
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        if let shortcut = element.properties["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "s", "keyboardShortcut.key should be 's'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["command", "shift"]), "keyboardShortcut.modifiers should be ['command', 'shift']")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testBuildViewAndApplyModifiersWithSpecialKeyKeyboardShortcut() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "View",
            "properties": {
                "keyboardShortcut": {"key": "return", "modifiers": ["option"]}
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
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        if let shortcut = element.properties["keyboardShortcut"] as? [String: Any] {
            XCTAssertEqual(shortcut["key"] as? String, "return", "keyboardShortcut.key should be 'return'")
            if let modifiers = shortcut["modifiers"] as? [String] {
                XCTAssertEqual(Set(modifiers), Set(["option"]), "keyboardShortcut.modifiers should be ['option']")
            } else {
                XCTFail("keyboardShortcut.modifiers should be an array")
            }
        } else {
            XCTFail("keyboardShortcut should be a dictionary")
        }
    }
    
    func testBuildViewAndApplyModifiersWithInvalidKeyboardShortcut() throws {
        let jsonString = """
            {
                "id": 1,
                "type": "View",
                "properties": {
                    "keyboardShortcut": {"key": "invalid", "modifiers": ["command"]}
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
        
        let validatedProperties = View.validateProperties(element.properties, logger)
        
        let view = View.buildView(element, viewModel, windowUUID, validatedProperties, logger)
        let _ = View.applyModifiers(view, element, windowUUID, validatedProperties, logger)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "buildView should return EmptyView")
        XCTAssertNil(validatedProperties["keyboardShortcut"], "keyboardShortcut should be nil for invalid key")
    }
}
