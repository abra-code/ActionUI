// Tests/Views/SafeAreaTests.swift
import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SafeAreaTests: XCTestCase {
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

    // MARK: - ignoresSafeArea (property)

    func testIgnoresSafeAreaBoolKept() {
        let mods = BaseModifiers(["ignoresSafeArea": true])
        XCTAssertEqual(mods.ignoresSafeArea, BaseModifiers.SafeArea())
    }

    func testIgnoresSafeAreaObjectKept() {
        let mods = BaseModifiers(["ignoresSafeArea": ["edges": "bottom", "regions": "container"]])
        XCTAssertEqual(mods.ignoresSafeArea, BaseModifiers.SafeArea(regions: .container, edges: .bottom))
    }

    func testIgnoresSafeAreaInvalidDropped() {
        let mods = BaseModifiers(["ignoresSafeArea": "yes"])
        XCTAssertNil(mods.ignoresSafeArea, "a non-Bool/non-object ignoresSafeArea is ignored")
    }

    // MARK: - safeAreaInset (subview slot)

    func testSafeAreaInsetDecodesAsSingleSubview() throws {
        let json = """
        {
          "id": 1, "type": "ScrollView", "properties": {},
          "safeAreaInset": {
            "id": 2, "type": "HStack",
            "properties": { "safeAreaEdge": "bottom", "safeAreaSpacing": 0.0 },
            "children": [ { "id": 3, "type": "Text", "properties": { "text": "Bar" } } ]
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        let inset = try XCTUnwrap(element.subviews?["safeAreaInset"] as? ActionUIElement)
        XCTAssertEqual(inset.type, "HStack")
        XCTAssertEqual(inset.properties["safeAreaEdge"] as? String, "bottom")
    }

    func testSafeAreaInsetIsATraversedChild() throws {
        // The inset view's id must register in the window's ViewModel pool.
        let json = """
        {
          "id": 1, "type": "ScrollView", "properties": {},
          "safeAreaInset": { "id": 2, "type": "Text", "properties": { "text": "Bar", "safeAreaEdge": "top" } }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertTrue(element.childElements.map { $0.id }.contains(2), "inset id is traversed")
    }

    func testSafeAreaInsetRoundTripEncode() throws {
        let json = """
        {
          "id": 1, "type": "ScrollView", "properties": {},
          "safeAreaInset": { "id": 2, "type": "Text", "properties": { "text": "Bar" } }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        let reEncoded = try JSONEncoder(logger: logger).encode(element)
        let roundTripped = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: reEncoded)
        XCTAssertNotNil(roundTripped.subviews?["safeAreaInset"] as? ActionUIElement)
    }

    func testSafeAreaInsetAbsent() throws {
        let json = """
        {"id": 1, "type": "ScrollView", "properties": {}}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: data)
        XCTAssertNil(element.subviews?["safeAreaInset"])
    }
}
