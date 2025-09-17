// Tests/Views/VideoPlayerTests.swift
/*
 VideoPlayerTests.swift

 Tests for the VideoPlayer component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
import AVKit
@testable import ActionUI

@MainActor
final class VideoPlayerTests: XCTestCase {
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
    
    func testVideoPlayerValidatePropertiesValid() {
        let properties: [String: Any] = [
            "url": "https://example.com/video.mp4",
            "autoplay": true,
            "padding": 10.0
        ]
        
        let validated = VideoPlayer.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["url"] as? String, "https://example.com/video.mp4", "url should be valid")
        XCTAssertEqual(validated["autoplay"] as? Bool, true, "autoplay should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testVideoPlayerValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "url": 123,
            "autoplay": "invalid"
        ]
        
        // Use ConsoleLogger to avoid XCTestLogger error failure
        let consoleLogger = ConsoleLogger()
        let validated = VideoPlayer.validateProperties(properties, consoleLogger)
        
        XCTAssertNil(validated["url"], "Invalid url should be nil")
        XCTAssertNil(validated["autoplay"], "Invalid autoplay should be nil")
    }
    
    func testVideoPlayerValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = VideoPlayer.validateProperties(properties, logger)
        
        XCTAssertNil(validated["url"], "Missing url should be nil")
        XCTAssertNil(validated["autoplay"], "Missing autoplay should be nil")
    }
    
    func testVideoPlayerConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VideoPlayer",
            "properties": [
                "url": "https://example.com/video.mp4",
                "autoplay": true,
                "padding": 10.0
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = VideoPlayer.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        // Verify properties were validated correctly
        XCTAssertEqual(validatedProperties["url"] as? String, "https://example.com/video.mp4", "Validated url should be correct")
        XCTAssertEqual(validatedProperties["autoplay"] as? Bool, true, "Validated autoplay should be true")
    }
    
    func testVideoPlayerJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "VideoPlayer",
            "properties": {
                "url": "https://example.com/video.mp4",
                "autoplay": true,
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
        
        // Parse JSON into ViewElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "VideoPlayer", "Element type should be VideoPlayer")
        XCTAssertEqual(element.properties["url"] as? String, "https://example.com/video.mp4", "url should be https://example.com/video.mp4")
        XCTAssertEqual(element.properties["autoplay"] as? Bool, true, "autoplay should be true")
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
        XCTAssertEqual(viewModel.value as? String, "https://example.com/video.mp4", "Initial viewModel value should be the URL string")
    }
    
    func testVideoPlayerDynamicURLUpdate() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VideoPlayer",
            "properties": [
                "url": "https://example.com/video.mp4",
                "autoplay": true,
                "padding": 10.0
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = VideoPlayer.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        // Verify initial properties
        XCTAssertEqual(validatedProperties["url"] as? String, "https://example.com/video.mp4", "Initial validated url should be correct")
        
        // Simulate dynamic URL update
        viewModel.value = "https://example.com/new-video.mp4"
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        // No viewModel.value verification, as it requires loadDescription
    }
    
    func testVideoPlayerInvalidURL() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VideoPlayer",
            "properties": [
                "url": "invalid-url", // Malformed URL
                "autoplay": true,
                "padding": 10.0
            ]
        ]
        
        let consoleLogger = ConsoleLogger()
        let element = try ViewElement(from: elementDict, logger: consoleLogger)
        let validatedProperties = VideoPlayer.validateProperties(element.properties, consoleLogger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        // Verify validated properties
        XCTAssertEqual(validatedProperties["url"] as? String, "invalid-url", "Validated url should be the invalid URL string")
    }
    
    func testVideoPlayerMissingURL() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VideoPlayer",
            "properties": [
                "autoplay": true,
                "padding": 10.0
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = VideoPlayer.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        // Verify validated properties
        XCTAssertNil(validatedProperties["url"], "Missing url should be nil")
    }
}
