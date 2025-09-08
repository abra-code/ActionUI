// ActionUITests/ActionUIContentViewTests.swift
/*
 ActionUIContentViewTests.swift

 Unit tests for ActionUIContentView, verifying bundle, local file URL, and network URL initialization.
 Uses a temporary bundle to simulate bundle resources and MockURLProtocol for network responses.
 Tests JSON without optional numerical IDs, aligning with ActionUIModel's auto-assignment.
*/

import XCTest
@testable import ActionUI
import SwiftUI

@MainActor
final class ActionUIContentViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    // JSON matching ContentView.json, used by all tests
    static let testJSON: String = """
    {
        "type": "VStack",
        "properties": {
            "alignment": "center"
        },
        "children": [
            {
                "type": "Image",
                "properties": {
                    "systemName": "globe",
                    "imageScale": "large",
                    "foregroundStyle": "tint",
                    "accessibilityIdentifier": "globe_image"
                }
            },
            {
                "type": "Text",
                "properties": {
                    "text": "Hello, world!",
                    "accessibilityIdentifier": "hello_text"
                }
            }
        ]
    }
    """

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        windowUUID = UUID().uuidString
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        URLProtocol.unregisterClass(MockURLProtocol.self)
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // Mock URLProtocol for network tests
    class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                XCTFail("No request handler set")
                return
            }
            do {
                let (data, response) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
    }

    func testBundleInit() async throws {
        // Arrange: Create a temporary bundle with the JSON file
        let jsonData = Self.testJSON.data(using: .utf8)!
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resourceDir = tempDir.appendingPathComponent("ActionUI.bundle")
        try FileManager.default.createDirectory(at: resourceDir, withIntermediateDirectories: true)
        let jsonURL = resourceDir.appendingPathComponent("TestContentView.json")
        try jsonData.write(to: jsonURL)
        let testBundle = Bundle(path: resourceDir.path)!

        // Act: Initialize ActionUIContentView with custom bundle
        let view = ActionUIContentView(resourceName: "TestContentView", resourceExtension: "json", bundle: testBundle, windowUUID: windowUUID, logger: logger)
        _ = view.body

        // Assert: Verify windowModel and viewModels
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID], "WindowModel should be initialized")
        let rootElement = try XCTUnwrap(windowModel.element, "Element should be loaded")
        XCTAssertEqual(rootElement.type, "VStack", "Root element should be VStack")
        XCTAssertEqual(rootElement.properties["alignment"] as? String, "center", "VStack alignment should be center")
        XCTAssertEqual(windowModel.viewModels.count, 3, "Should have root, Image, and Text viewModels")
        let children = try XCTUnwrap(rootElement.subviews?["children"] as? [any ActionUIElement], "VStack should have children")
        XCTAssertEqual(children.count, 2, "VStack should have 2 children")
        let imageElement = children.first { $0.type == "Image" }
        let textElement = children.first { $0.type == "Text" }
        let imageViewModel = try XCTUnwrap(imageElement.map { windowModel.viewModels[$0.id] }, "Image viewModel should exist")
        let textViewModel = try XCTUnwrap(textElement.map { windowModel.viewModels[$0.id] }, "Text viewModel should exist")
        XCTAssertEqual(imageViewModel?.validatedProperties["systemName"] as? String, "globe", "Image should have systemName 'globe'")
        XCTAssertEqual(imageViewModel?.validatedProperties["imageScale"] as? String, "large", "Image should have imageScale 'large'")
        XCTAssertEqual(imageViewModel?.validatedProperties["foregroundStyle"] as? String, "tint", "Image should have foregroundStyle 'tint'")
        XCTAssertEqual(imageViewModel?.validatedProperties["accessibilityIdentifier"] as? String, "globe_image", "Image should have accessibilityIdentifier 'globe_image'")
        XCTAssertEqual(textViewModel?.validatedProperties["text"] as? String, "Hello, world!", "Text should have text 'Hello, world!'")
        XCTAssertEqual(textViewModel?.validatedProperties["accessibilityIdentifier"] as? String, "hello_text", "Text should have accessibilityIdentifier 'hello_text'")

        // Clean up
        try FileManager.default.removeItem(at: tempDir)
    }

    func testLocalFileURLInit() async throws {
        // Arrange: Create a temporary JSON file
        let jsonData = Self.testJSON.data(using: .utf8)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("TestContentView.json")
        try jsonData.write(to: tempURL)

        // Act: Initialize ActionUIContentView with file URL
        let view = ActionUIContentView(url: tempURL, windowUUID: windowUUID, logger: logger)
        _ = view.body

        // Assert: Verify windowModel and viewModels
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID], "WindowModel should be initialized")
        let rootElement = try XCTUnwrap(windowModel.element, "Element should be loaded")
        XCTAssertEqual(rootElement.type, "VStack", "Root element should be VStack")
        XCTAssertEqual(rootElement.properties["alignment"] as? String, "center", "VStack alignment should be center")
        XCTAssertEqual(windowModel.viewModels.count, 3, "Should have root, Image, and Text viewModels")
        let children = try XCTUnwrap(rootElement.subviews?["children"] as? [any ActionUIElement], "VStack should have children")
        XCTAssertEqual(children.count, 2, "VStack should have 2 children")
        let imageElement = children.first { $0.type == "Image" }
        let textElement = children.first { $0.type == "Text" }
        let imageViewModel = try XCTUnwrap(imageElement.map { windowModel.viewModels[$0.id] }, "Image viewModel should exist")
        let textViewModel = try XCTUnwrap(textElement.map { windowModel.viewModels[$0.id] }, "Text viewModel should exist")
        XCTAssertEqual(imageViewModel?.validatedProperties["systemName"] as? String, "globe", "Image should have systemName 'globe'")
        XCTAssertEqual(imageViewModel?.validatedProperties["imageScale"] as? String, "large", "Image should have imageScale 'large'")
        XCTAssertEqual(imageViewModel?.validatedProperties["foregroundStyle"] as? String, "tint", "Image should have foregroundStyle 'tint'")
        XCTAssertEqual(imageViewModel?.validatedProperties["accessibilityIdentifier"] as? String, "globe_image", "Image should have accessibilityIdentifier 'globe_image'")
        XCTAssertEqual(textViewModel?.validatedProperties["text"] as? String, "Hello, world!", "Text should have text 'Hello, world!'")
        XCTAssertEqual(textViewModel?.validatedProperties["accessibilityIdentifier"] as? String, "hello_text", "Text should have accessibilityIdentifier 'hello_text'")

        // Clean up
        try FileManager.default.removeItem(at: tempURL)
    }

    func testNetworkURLInit() async throws {
        // Arrange: Mock network response
        let jsonData = Self.testJSON.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (jsonData, response)
        }

        // Set up cache directory
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("ActionUICache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Act: Initialize ActionUIContentView with network URL and trigger body
        let testURL = URL(string: "https://example.com/TestContentView.json")!
        let view = ActionUIContentView(url: testURL, windowUUID: windowUUID, logger: logger)
        _ = view.body

        // Wait for async network task
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Assert: Verify windowModel and viewModels
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID], "WindowModel should be initialized")
        let rootElement = try XCTUnwrap(windowModel.element, "Element should be loaded")
        XCTAssertEqual(rootElement.type, "VStack", "Root element should be VStack")
        XCTAssertEqual(rootElement.properties["alignment"] as? String, "center", "VStack alignment should be center")
        XCTAssertEqual(windowModel.viewModels.count, 3, "Should have root, Image, and Text viewModels")
        let children = try XCTUnwrap(rootElement.subviews?["children"] as? [any ActionUIElement], "VStack should have children")
        XCTAssertEqual(children.count, 2, "VStack should have 2 children")
        let imageElement = children.first { $0.type == "Image" }
        let textElement = children.first { $0.type == "Text" }
        let imageViewModel = try XCTUnwrap(imageElement.map { windowModel.viewModels[$0.id] }, "Image viewModel should exist")
        let textViewModel = try XCTUnwrap(textElement.map { windowModel.viewModels[$0.id] }, "Text viewModel should exist")
        XCTAssertEqual(imageViewModel?.validatedProperties["systemName"] as? String, "globe", "Image should have systemName 'globe'")
        XCTAssertEqual(imageViewModel?.validatedProperties["imageScale"] as? String, "large", "Image should have imageScale 'large'")
        XCTAssertEqual(imageViewModel?.validatedProperties["foregroundStyle"] as? String, "tint", "Image should have foregroundStyle 'tint'")
        XCTAssertEqual(imageViewModel?.validatedProperties["accessibilityIdentifier"] as? String, "globe_image", "Image should have accessibilityIdentifier 'globe_image'")
        XCTAssertEqual(textViewModel?.validatedProperties["text"] as? String, "Hello, world!", "Text should have text 'Hello, world!'")
        XCTAssertEqual(textViewModel?.validatedProperties["accessibilityIdentifier"] as? String, "hello_text", "Text should have accessibilityIdentifier 'hello_text'")

        // Verify cache
        let cacheURL = DirectoryHelper.cacheURL(for: windowUUID, resourceName: "TestContentView", resourceExtension: "plist", logger: logger)!
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path), "Cache file should exist")

        // Clean up
        try FileManager.default.removeItem(at: cacheDir)
    }
}
