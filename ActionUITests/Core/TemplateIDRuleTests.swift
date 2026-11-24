// Core/TemplateIDRuleTests.swift
/*
 Less-trusted content may not reuse a trusted element's id, and that includes the ids in its
 templates (a List's or a Table's row blueprint, at any depth) and in a Chart's annotations: their
 elements get no view model, but they keep the ids their JSON gives them, and a container may find
 one by its id.
*/

import XCTest
@testable import ActionUI

// Records error messages without failing the test, for a refusal logged on purpose.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { errors.append(message) }
    }
}

@MainActor
final class TemplateIDRuleTests: XCTestCase {
    private var windowUUID: String!
    private var recording: RecordingLogger!

    override func setUp() async throws {
        // No super.setUp(): see ActionUIContentLoaderTests.
        recording = RecordingLogger()
        ActionUIModel.shared.logger = recording
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        let root = Data(#"{ "id": 1, "type": "VStack", "children": [ { "id": 2, "type": "Button", "properties": { "title": "Mine" } }, { "id": 100, "type": "LoadableView", "properties": {} } ] }"#.utf8)
        _ = try ActionUIContentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    private let remote = ActionUIContentLoader.Source.remote(URL(string: "https://example.com/panel.json")!)

    private func loadRemote(_ json: String) throws {
        _ = try ActionUIContentLoader.load(data: Data(json.utf8), format: "json", windowUUID: windowUUID, isContentView: false,
                                            parentID: 100, source: remote)
    }

    func testATemplatesIDsAreFoundAtAnyDepth() throws {
        let json = #"{ "id": 10, "type": "List", "template": { "id": 11, "type": "VStack", "children": [ { "id": 12, "type": "Text" }, { "type": "List", "template": { "id": 13, "type": "Text" } } ] } }"#
        let element = try JSONDecoder().decode(ActionUIElement.self, from: Data(json.utf8))
        let ids = WindowModel.templateIDs(in: element)
        XCTAssertEqual(Set(ids.filter { $0 > 0 }), [11, 12, 13])
        XCTAssertFalse(ids.contains(10), "not the List's own id")
    }

    func testLessTrustedContentWhoseTemplateReusesATrustedIDIsRefused() throws {
        // The template's Button takes the host's Button id 2.
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "List", "template": { "id": 2, "type": "Button", "properties": { "title": "Theirs" } } }"#)) { error in
            XCTAssertEqual("\(error)", "id conflict: 2 already in the window")
        }
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200), "nothing of it is loaded")
        XCTAssertEqual(recording.errors, ["Not loading a less-trusted sub-view for parent 100: id 2 is already in the window"])
        // Deeper in a nested template too.
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "List", "template": { "id": 201, "type": "VStack", "children": [ { "type": "List", "template": { "id": 1, "type": "Text" } } ] } }"#))
        // A template inside a live element's sheet.
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "VStack", "sheet": { "id": 202, "type": "List", "template": { "id": 2, "type": "Button" } } }"#))
    }

    func testANegativeIDInATemplatesOverlayIsNotKept() throws {
        // A negative id the JSON gives is replaced by a generated one, in a template's overlay as
        // anywhere else, so it cannot name a trusted element that has no id of its own: here one
        // whose generated id the less-trusted JSON names.
        let trusted = try ActionUIContentLoader.load(data: Data(#"{ "type": "Button", "properties": { "title": "Mine" } }"#.utf8),
                                                      format: "json", windowUUID: windowUUID, isContentView: false, parentID: 0, source: nil)
        XCTAssertLessThan(trusted.id, -1, "a generated id")
        XCTAssertNoThrow(try loadRemote(#"{ "id": 200, "type": "List", "template": { "id": 201, "type": "Text", "overlay": { "id": \#(trusted.id), "type": "Button" } } }"#))
        XCTAssertEqual(recording.errors, [])
    }

    /// A Chart whose BarMark has an annotation with `content`, drawn per mark like a template row.
    private func chart(annotation content: String) -> String {
        #"{ "id": 200, "type": "Chart", "properties": { "chart": { "columns": ["day", { "name": "high", "type": "number" }], "content": [ { "type": "ForEach", "content": [ { "type": "BarMark", "x": { "label": "Day", "value": "$day" }, "y": { "label": "High", "value": "$high" }, "annotation": { "content": \#(content) } } ] } ] } } }"#
    }

    func testAChartsAnnotationsCountAsTemplates() throws {
        let annotation = #"{ "id": 300, "type": "VStack", "children": [ { "id": 2, "type": "Button", "properties": { "title": "Theirs" } } ] }"#
        let element = try JSONDecoder().decode(ActionUIElement.self, from: Data(chart(annotation: annotation).utf8))
        XCTAssertEqual(Set(WindowModel.templateIDs(in: element).filter { $0 > 0 }), [300, 2])
        // Its Button takes the host's Button id 2: refused.
        XCTAssertThrowsError(try loadRemote(chart(annotation: annotation))) { error in
            XCTAssertEqual("\(error)", "id conflict: 2 already in the window")
        }
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200), "nothing of it is loaded")
        // An annotation whose ids nothing trusted has loads.
        try loadRemote(chart(annotation: #"{ "id": 301, "type": "Text", "properties": { "text": "$high" } }"#))
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200)?.trust, .lessTrusted)
    }

    func testAnnotationsOutsideAForEachInAPlotOrInATemplateRowAreCheckedToo() throws {
        let button = #"{ "id": 2, "type": "Button", "properties": { "title": "Theirs" } }"#
        let rule = #"{ "type": "RuleMark", "y": { "label": "Goal", "value": 10 }, "annotation": { "content": \#(button) } }"#
        // On a mark at the top level of the content.
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "Chart", "properties": { "chart": { "content": [ \#(rule) ] } } }"#))
        // On a Plot, whose annotation goes on each mark inside.
        let plot = #"{ "type": "Plot", "annotation": { "content": \#(button) }, "content": [ { "type": "RuleMark", "y": { "label": "Goal", "value": 10 } } ] }"#
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "Chart", "properties": { "chart": { "content": [ \#(plot) ] } } }"#))
        // A template inside an annotation.
        let list = #"{ "type": "List", "template": \#(button) }"#
        let listRule = #"{ "type": "RuleMark", "y": { "label": "Goal", "value": 10 }, "annotation": { "content": \#(list) } }"#
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "Chart", "properties": { "chart": { "content": [ \#(listRule) ] } } }"#))
        // A Chart in a template row.
        XCTAssertThrowsError(try loadRemote(#"{ "id": 200, "type": "List", "template": { "type": "Chart", "properties": { "chart": { "content": [ \#(rule) ] } } } }"#))
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200), "nothing of it is loaded")
        XCTAssertEqual(recording.errors.count, 4, "\(recording.errors)")
    }

    func testTemplateIDsThatNothingTrustedHasLoad() throws {
        try loadRemote(#"{ "id": 200, "type": "List", "template": { "id": 201, "type": "Button", "properties": { "title": "Row" } } }"#)
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200)?.trust, .lessTrusted)
        XCTAssertTrue(recording.errors.isEmpty, "\(recording.errors)")
    }

    func testTheHostsOwnTemplatesMayReuseItsIDs() throws {
        // The rule is for less-trusted content: the host's own sub-view may.
        _ = try ActionUIContentLoader.load(data: Data(#"{ "id": 200, "type": "List", "template": { "id": 2, "type": "Text" } }"#.utf8),
                                            format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100, source: nil)
        XCTAssertTrue(recording.errors.isEmpty, "\(recording.errors)")
    }
}
