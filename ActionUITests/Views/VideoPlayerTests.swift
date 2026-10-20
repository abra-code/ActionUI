// Tests/Views/VideoPlayerTests.swift
/*
 VideoPlayerTests.swift

 Tests for the VideoPlayer component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and state binding.
*/

import XCTest
import SwiftUI
import AVKit
@testable import ActionUI

@MainActor
final class VideoPlayerTests: XCTestCase {
    private var logger: XCTestLogger!
    private var consoleLogger: ConsoleLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        consoleLogger = ConsoleLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        consoleLogger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testVideoPlayerPropsValid() {
        let properties: [String: Any] = [
            "url": "https://example.com/video.mp4",
            "autoplay": true,
            "padding": 10.0
        ]
        
        let props = VideoPlayer.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.url, "https://example.com/video.mp4", "url should be valid")
        XCTAssertEqual(props.autoplay, true, "autoplay should be valid")
        XCTAssertEqual(mods.padding, .uniform(10.0), "padding should be passed through")
    }
    
    func testVideoPlayerPropsIgnoreInvalidValues() {
        // Use ConsoleLogger to avoid test failure from expected error
        ActionUIModel.shared.logger = consoleLogger

        let properties: [String: Any] = [
            "url": 123,
            "autoplay": "invalid"
        ]
        
        let props = VideoPlayer.Props(properties)
        
        XCTAssertNil(props.url, "Invalid url should be nil")
        XCTAssertNil(props.autoplay, "Invalid autoplay should be nil")

        ActionUIModel.shared.logger = logger
    }
    
    func testVideoPlayerPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = VideoPlayer.Props(properties)
        
        XCTAssertNil(props.url, "Missing url should be nil")
        XCTAssertNil(props.autoplay, "Missing autoplay should be nil")
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
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.seedProperties(element.properties)
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        // Verify properties were read correctly
        let props = VideoPlayer.Props(properties)
        XCTAssertEqual(props.url, "https://example.com/video.mp4", "url should be correct")
        XCTAssertEqual(props.autoplay, true, "autoplay should be true")
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
        
        // Parse JSON into ActionUIElement
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
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.seedProperties(element.properties)
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        // Verify initial properties
        XCTAssertEqual(VideoPlayer.Props(properties).url, "https://example.com/video.mp4", "Initial url should be correct")
        
        // Simulate dynamic URL update
        viewModel.value = "https://example.com/new-video.mp4"
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        // No viewModel.value verification, as it requires loadDescription
    }
    
    func testVideoPlayerInvalidURL() throws {
        // Use ConsoleLogger to avoid test failure from expected error
        ActionUIModel.shared.logger = consoleLogger

        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VideoPlayer",
            "properties": [
                "url": "invalid-url", // Malformed URL
                "autoplay": true,
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.seedProperties(element.properties)
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        // Verify properties
        XCTAssertEqual(VideoPlayer.Props(properties).url, "invalid-url", "url should be the invalid URL string")

        ActionUIModel.shared.logger = logger
    }
    
    func testVideoPlayerMissingURL() throws {
        // Use ConsoleLogger to avoid test failure from expected error
        ActionUIModel.shared.logger = consoleLogger

        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VideoPlayer",
            "properties": [
                "autoplay": true,
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        viewModel.seedProperties(element.properties)
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        // Verify properties
        XCTAssertNil(VideoPlayer.Props(properties).url, "Missing url should be nil")

        ActionUIModel.shared.logger = logger
    }
}
