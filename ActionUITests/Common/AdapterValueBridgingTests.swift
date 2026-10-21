// Tests/Common/AdapterValueBridgingTests.swift
/*
 Values as the adapters hand them to the model: JSON text parsed and made Swift-native
 (FoundationBridge.native), then stored through setElementValue and setElementState, which bring
 a number to the type the element or state holds (ValueCoercion).
*/

import Foundation
import XCTest
@testable import ActionUI

@MainActor
final class AdapterValueBridgingTests: XCTestCase {
    private let model = ActionUIModel.shared
    private var windowUUID = ""

    override func setUp() async throws {
        try await super.setUp()
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        let description: [String: Any] = [
            "id": 100, "type": "VStack",
            "children": [
                ["id": 1, "type": "Slider", "properties": [:]],
                ["id": 2, "type": "Toggle", "properties": ["title": "On"]],
                ["id": 3, "type": "TabView", "children": []],
                ["id": 4, "type": "Text", "properties": ["text": "states"]],
            ],
        ]
        _ = try model.loadDescription(from: description, windowUUID: windowUUID)
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        try await super.tearDown()
    }

    private func parsed(_ json: String) throws -> Any {
        FoundationBridge.native(try ActionUIJSON.value(from: json))
    }

    private func storedValue(_ viewID: Int) -> String {
        model.getElementValue(windowUUID: windowUUID, viewID: viewID).map { "\(type(of: $0)) \($0)" } ?? "nil"
    }

    // MARK: - Element values

    func testNumbersReachTheElementsType() throws {
        model.setElementValue(windowUUID: windowUUID, viewID: 1, value: try parsed("5"))
        XCTAssertEqual(storedValue(1), "Double 5.0", "A Slider stores a Double")
        model.setElementValue(windowUUID: windowUUID, viewID: 3, value: try parsed("2.0"))
        XCTAssertEqual(storedValue(3), "Int 2", "A TabView stores an Int")
    }

    func testASwiftHostsIntReachesASlider() {
        model.setElementValue(windowUUID: windowUUID, viewID: 1, value: 4)
        XCTAssertEqual(storedValue(1), "Double 4.0", "Before coercion a Swift Int stayed an Int, which the Slider ignored")
    }

    func testAToggleTakesZeroAndOne() throws {
        model.setElementValue(windowUUID: windowUUID, viewID: 2, value: try parsed("1"))
        XCTAssertEqual(storedValue(2), "Bool true")
        model.setElementValue(windowUUID: windowUUID, viewID: 2, value: try parsed("0"))
        XCTAssertEqual(storedValue(2), "Bool false")
        model.setElementValue(windowUUID: windowUUID, viewID: 2, value: try parsed("true"))
        XCTAssertEqual(storedValue(2), "Bool true")
        model.setElementValue(windowUUID: windowUUID, viewID: 2, value: try parsed("2"))
        XCTAssertEqual(storedValue(2), "Int 2", "Only 0 and 1 become a Bool, as NSNumber bridging allowed")
    }

    func testAJSONNullIsStoredAndLeavesAsNSNull() throws {
        model.setElementValue(windowUUID: windowUUID, viewID: 4, value: try parsed("null"))
        let stored = model.getElementValue(windowUUID: windowUUID, viewID: 4)
        XCTAssertTrue(stored is ActionUIJSONNull)
        XCTAssertTrue(stored.map(FoundationBridge.foundation) is NSNull, "What the Objective-C and JavaScript adapters return")
        XCTAssertEqual(model.getElementValueAsString(windowUUID: windowUUID, viewID: 4), "<null>", "The text an NSNull value gave")

        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "nothing", value: try parsed("null")))
        XCTAssertEqual(model.getElementStateAsString(windowUUID: windowUUID, viewID: 4, key: "nothing"), "<null>", "The text an NSNull state gave")
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "list", value: try parsed("[1,null]")))
        XCTAssertEqual(model.getElementStateAsString(windowUUID: windowUUID, viewID: 4, key: "list"), "[1, <null>]", "A null inside a container too")
    }

    // MARK: - States

    func testAnExistingNumberStateTakesAnotherNumberType() throws {
        model.setElementState(windowUUID: windowUUID, viewID: 4, key: "ratio", value: 0.5)
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "ratio", value: try parsed("3")))
        let ratio = model.getElementState(windowUUID: windowUUID, viewID: 4, key: "ratio")
        XCTAssertEqual(ratio.map { "\(type(of: $0)) \($0)" }, "Double 3.0")

        model.setElementState(windowUUID: windowUUID, viewID: 4, key: "count", value: 1)
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "count", value: try parsed("2.0")))
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 4, key: "count") as? Int, 2)
    }

    // A host that creates a state with 5 and then sets 5.5: JSON cannot say 5.0.
    func testAnIntStateWidensToDouble() throws {
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "level", value: try parsed("5")))
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "level", value: try parsed("5.5")))
        var level = model.getElementState(windowUUID: windowUUID, viewID: 4, key: "level")
        XCTAssertEqual(level.map { "\(type(of: $0)) \($0)" }, "Double 5.5")
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "level", value: try parsed("6")))
        level = model.getElementState(windowUUID: windowUUID, viewID: 4, key: "level")
        XCTAssertEqual(level.map { "\(type(of: $0)) \($0)" }, "Double 6.0", "Once a Double, an integral number is brought to Double")
    }

    func testABoolStateTakesOnlyABool() throws {
        let quiet = SilentLogger()
        let saved = model.logger
        model.logger = quiet
        defer { model.logger = saved }

        model.setElementState(windowUUID: windowUUID, viewID: 4, key: "flag", value: false)
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "flag", value: try parsed("true")))
        XCTAssertFalse(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "flag", value: try parsed("1")),
                       "Unlike an element value, a Bool state has never accepted 1")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 4, key: "flag") as? Bool, true)
    }

    func testANewStateKeepsTheParsedType() throws {
        XCTAssertTrue(model.setElementState(windowUUID: windowUUID, viewID: 4, key: "fresh", value: try parsed("7")))
        let fresh = model.getElementState(windowUUID: windowUUID, viewID: 4, key: "fresh")
        XCTAssertEqual(fresh.map { "\(type(of: $0)) \($0)" }, "Int 7")
        XCTAssertEqual(model.getElementStateAsString(windowUUID: windowUUID, viewID: 4, key: "fresh"), "7")
    }
}

private final class SilentLogger: ActionUILogger, @unchecked Sendable {
    func log(_ message: String, _ level: LoggerLevel) {}
}
