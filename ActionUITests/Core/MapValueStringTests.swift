// Core/MapValueStringTests.swift
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
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
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

    // Read by Map's own parser (Map.coordinate(fromJSON:)): integral numbers count, other keys are ignored.
    func testACoordinateWithIntegralNumbersAndAnotherKey() {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: #"{"latitude":40,"longitude":-74,"label":"NYC"}"#)
        XCTAssertEqual(model.getElementValue(windowUUID: windowUUID, viewID: 1) as? ActionUICoordinate,
                       ActionUICoordinate(latitude: 40, longitude: -74))
    }

    func testAnInvalidStringLeavesTheValue() {
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "not a coordinate")
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: #"{"latitude":"north"}"#)
        model.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: #"{"latitude":true,"longitude":false}"#)
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 1),
                       #"{"latitude":37.0,"longitude":-122.5}"#)
    }
}
