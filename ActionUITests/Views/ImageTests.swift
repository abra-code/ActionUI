// Tests/Views/ImageTests.swift
/*
 ImageTests.swift

 Tests for the Image component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ImageTests: XCTestCase {
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
    
    func testImageConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Image",
            "properties": [
                "systemName": "star.fill",
                "resizable": true,
                "contentMode": "fit",
                "padding": 10.0
            ]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should be an EmptyView")
    }
    
    func testImageJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Image",
            "properties": {
                "systemName": "star.fill",
                "resizable": true,
                "contentMode": "fit",
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
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "star.fill", "systemName should be star.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, true, "resizable should be true")
        XCTAssertEqual(element.properties["contentMode"] as? String, "fit", "contentMode should be fit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testImagePropsValid() {
        let properties: [String: Any] = [
            "systemName": "star.fill",
            "resizable": true,
            "contentMode": "fit",
            "imageScale": "large",
            "padding": 10.0
        ]
        
        let props = Image.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.sources, [.systemName("star.fill")], "systemName should be preserved")
        XCTAssertTrue(props.resizable, "resizable should be preserved")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be preserved")
        XCTAssertEqual(props.imageScale, .large, "imageScale should be preserved")
        XCTAssertEqual(mods.padding, .uniform(10.0), "padding should be passed through")
    }
    
    func testImagePropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "systemName": 123,
            "resizable": "true",
            "contentMode": "invalid",
            "imageScale": "huge",
            "filePath": "/path/to/doc.txt"
        ]
        
        let props = Image.Props(properties)
        
        XCTAssertTrue(props.sources.allSatisfy { if case .systemName = $0 { return false } else { return true } }, "Invalid systemName should be ignored")
        XCTAssertFalse(props.resizable, "Invalid resizable should be ignored")
        XCTAssertNil(props.contentMode, "Invalid contentMode should be nil")
        XCTAssertNil(props.imageScale, "Invalid imageScale should be nil")
        // A filePath that is not an image or PDF is kept as a source; the renderer skips it.
        XCTAssertEqual(props.sources, [.filePath("/path/to/doc.txt")], "only the filePath is a String source")
    }
    
    func testImagePropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Image.Props(properties)
        
        XCTAssertTrue(props.sources.isEmpty, "Empty properties should result in no sources")
        XCTAssertFalse(props.resizable, "Missing resizable should be the default")
        XCTAssertNil(props.contentMode, "Missing contentMode should be nil")
        XCTAssertNil(props.imageScale, "Missing imageScale should be nil")
    }
    
    func testImagePropsFilePathValid() {
        let properties: [String: Any] = [
            "filePath": "/path/to/image.jpg",
            "resizable": false,
            "contentMode": "fill",
            "imageScale": "small"
        ]

        let props = Image.Props(properties)

        XCTAssertEqual(props.sources, [.filePath("/path/to/image.jpg")], "Valid filePath should be preserved")
        XCTAssertFalse(props.resizable, "resizable should be preserved")
        XCTAssertEqual(props.contentMode, .fill, "contentMode should be preserved")
        XCTAssertEqual(props.imageScale, .small, "imageScale should be preserved")
    }

    func testImageContentModeValid() {
        let fitProps: [String: Any] = ["systemName": "star", "contentMode": "fit"]
        XCTAssertEqual(Image.Props(fitProps).contentMode, .fit, "contentMode 'fit' should be preserved")

        let fillProps: [String: Any] = ["systemName": "star", "contentMode": "fill"]
        XCTAssertEqual(Image.Props(fillProps).contentMode, .fill, "contentMode 'fill' should be preserved")
    }

    func testImageContentModeInvalid() {
        let properties: [String: Any] = ["systemName": "star", "contentMode": "stretch"]
        let props = Image.Props(properties)
        XCTAssertNil(props.contentMode, "Invalid contentMode should be ignored")
    }

    func testImageContentModeTakesPrecedenceOverScaleMode() {
        // When both are present, contentMode wins
        let properties: [String: Any] = [
            "systemName": "star",
            "contentMode": "fit",
            "scaleMode": "fill"
        ]
        let props = Image.Props(properties)
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be kept")
    }

    func testImageScaleModeBackwardCompat() {
        // scaleMode still works when contentMode is absent (deprecated but functional)
        let properties: [String: Any] = ["systemName": "star", "scaleMode": "fill"]
        let props = Image.Props(properties)
        XCTAssertEqual(props.contentMode, .fill, "scaleMode should be read when contentMode is absent")
    }
    
    func testImageJSONDecodingWithImageScale() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Image",
            "properties": {
                "systemName": "heart.fill",
                "resizable": false,
                "imageScale": "small",
                "padding": 5.0
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
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "heart.fill", "systemName should be heart.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, false, "resizable should be false")
        XCTAssertEqual(element.properties["imageScale"] as? String, "small", "imageScale should be small")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 5.0, "padding should be 5.0")
    }
}
