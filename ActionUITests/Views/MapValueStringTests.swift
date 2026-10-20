// Views/MapValueStringTests.swift
/*
 The string forms of a Map's value (its center coordinate), as the C interface and every language
 binding exchange them: getElementValueAsString / setElementValueFromString with no content type
 and with "json". The value's Swift type may change; these strings must not.
*/

import XCTest
@testable import ActionUI

@MainActor
final class MapValueStringTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    private let model = ActionUIModel.shared

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        model.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        _ = try model.loadDescription(from: [
            "type": "Map", "id": 1,
            "properties": ["coordinate": ["latitude": 37.0, "longitude": -122.5]],
        ], windowUUID: windowUUID)
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    func testTheInitialCoordinateAsAString() {
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 1),
                       #"{"latitude":37.0,"longitude":-122.5}"#)
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 1, contentType: "json"),
                       #"{"latitude":37,"longitude":-122.5}"#)
    }

    func testACoordinateSetFromAString() {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: #"{"latitude":40.7128,"longitude":-74.006}"#)
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 1),
                       #"{"latitude":40.7128,"longitude":-74.006}"#)
    }

    func testACoordinateSetFromAJSONString() {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: #"{"latitude":1.5,"longitude":2.25}"#, contentType: "json")
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 1),
                       #"{"latitude":1.5,"longitude":2.25}"#)
    }

    func testAnInvalidStringLeavesTheValue() {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "not a coordinate")
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: #"{"latitude":"north"}"#)
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 1),
                       #"{"latitude":37.0,"longitude":-122.5}"#)
    }
}
