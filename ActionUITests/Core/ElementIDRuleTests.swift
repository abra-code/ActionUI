// Core/ElementIDRuleTests.swift
/*
 Ids in ActionUI JSON are positive. An id of 0 would make an element pass for the host (whose own
 actions are judged as viewID 0) and a negative one for an element with no id of its own (those get
 generated negative ids), so either is replaced by a generated id, with a warning. Two elements of
 one ActionUI JSON with one id share a state, which is logged.
*/

import XCTest
@testable import ActionUI

// Records warnings and errors without failing the test.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var warnings: [String] = []
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .warning { warnings.append(message) }
        if level == .error { errors.append(message) }
    }
}

@MainActor
final class ElementIDRuleTests: XCTestCase {
    private var windowUUID: String!
    private var recording: RecordingLogger!

    override func setUp() async throws {
        // No super.setUp(): see ActionUIContentLoaderTests.
        recording = RecordingLogger()
        ActionUIModel.shared.logger = recording
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    private func load(_ json: String) throws -> ActionUIElement {
        try ActionUIContentLoader.load(data: Data(json.utf8), format: "json", windowUUID: windowUUID, isContentView: true,
                                        parentID: 0, source: nil)
    }

    func testAZeroOrNegativeIDIsReplacedByAGeneratedOne() throws {
        let root = try load(#"{ "id": 1, "type": "VStack", "children": [ { "id": 0, "type": "Button" }, { "id": -9, "type": "Text" }, { "id": 3, "type": "Text" } ] }"#)
        let ids = (root.subviews?["children"] as? [ActionUIElement])?.map(\.id) ?? []
        XCTAssertEqual(ids.count, 3)
        XCTAssertLessThan(ids[0], -1, "0 becomes a generated id")
        // Not "!= -9": the counter is process-wide and may reach -9 itself.
        XCTAssertEqual(ids[1], ids[0] - 1, "a negative id from JSON is not kept: the next generated id replaces it")
        XCTAssertEqual(ids[2], 3, "a positive id is kept")
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 0), "no element is known by the id 0")
        XCTAssertEqual(recording.warnings, ["Ignoring id 0 on Button: an id must be a positive integer",
                                            "Ignoring id -9 on Text: an id must be a positive integer"])
    }

    func testTheSameRuleForADictionary() throws {
        let element = try ActionUIElement(from: ["id": 0, "type": "Text"], logger: recording)
        XCTAssertLessThan(element.id, -1)
        XCTAssertEqual(try ActionUIElement(from: ["id": 5, "type": "Text"], logger: recording).id, 5)
        XCTAssertEqual(recording.warnings, ["Ignoring id 0 on Text: an id must be a positive integer"])
    }

    func testADuplicateIDIsLogged() throws {
        _ = try load(#"{ "id": 1, "type": "VStack", "children": [ { "id": 2, "type": "Text" }, { "type": "HStack", "children": [ { "id": 2, "type": "Button" } ] } ] }"#)
        XCTAssertEqual(recording.errors, ["Duplicate id 2 in window \(windowUUID!): its elements share one state"])
    }
}
