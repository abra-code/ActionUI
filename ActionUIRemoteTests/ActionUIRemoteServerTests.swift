// ActionUIRemoteTests/ActionUIRemoteServerTests.swift
//
// Drives a real ActionUIRemoteServer over a real socket against a headless window loaded into
// ActionUIModel.shared. The socket client runs on a background queue while the test pumps the
// main run loop through XCTest's wait(for:): the server hops every request to the main queue,
// so a blocking read on the main thread would starve it and every request would time out.

#if os(macOS)

import XCTest
import Darwin
@testable import ActionUI
@testable import ActionUIRemote

/// An error reply, surfaced to the test as a thrown error.
private struct RPCFailure: Error {
    let code: Int
    let message: String
    let id: Int?
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

@MainActor
final class ActionUIRemoteServerTests: XCTestCase {

    private var socketPath: String!
    private var windowUUID: String!
    private var server: ActionUIRemoteServer!
    private var client: TestSocketClient!
    private var nextID = 1
    private let clientQueue = DispatchQueue(label: "test.client")

    override func setUp() async throws {
        try await super.setUp()
        ActionUIModel.resetForRemoteTests()
        let logger = QuietLogger(maxLevel: .warning)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger

        windowUUID = UUID().uuidString
        try loadFixtureWindow(uuid: windowUUID)

        socketPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("aui-rpc-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock").path
        server = ActionUIRemoteServer(host: .init(name: "TestHost", version: "0.1"))
        server.logger = logger
        try server.start(socketPath: socketPath)
        client = try TestSocketClient(path: socketPath, timeoutSeconds: 10)
    }

    override func tearDown() async throws {
        client = nil
        server?.stop()
        server = nil
        unlink(socketPath)
        ActionUIModel.resetForRemoteTests()
        try await super.tearDown()
    }

    // MARK: - Fixture

    /// VStack 10 containing TextField 2, Toggle 3, Table 5 (two columns), DatePicker 6,
    /// Grid 7 with one row, Text 11.
    private func loadFixtureWindow(uuid: String) throws {
        let description: [String: Any] = [
            "id": 10,
            "type": "VStack",
            "children": [
                ["id": 2, "type": "TextField", "properties": ["title": "Name"]],
                ["id": 3, "type": "Toggle", "properties": ["title": "On"]],
                ["id": 5, "type": "Table", "properties": ["itemType": ["viewType": "Text"], "columns": ["A", "B"]]],
                ["id": 6, "type": "DatePicker", "properties": ["title": "When"]],
                ["id": 7, "type": "Grid", "rows": [[["id": 70, "type": "Text", "properties": ["text": "r0c0"]]]]],
                ["id": 11, "type": "Text", "properties": ["text": "hello"]],
            ],
        ]
        _ = try ActionUIModel.shared.loadDescription(from: description, windowUUID: uuid)
    }

    // MARK: - RPC helpers (client work on a background queue, main run loop pumped by wait)

    /// Send one raw line and read one reply line, off the main thread.
    private func exchange(_ line: String, expectReply: Bool = true, timeout: TimeInterval = 10) -> String? {
        let box = ResultBox<String>()
        let done = expectation(description: "reply")
        let client = self.client!
        clientQueue.async {
            client.write(line + "\n")
            if expectReply {
                box.value = client.readLine()
            }
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
        return box.value
    }

    private func requestLine(_ method: String, _ params: [String: Any], id: Any?) throws -> String {
        var envelope: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { envelope["id"] = id }
        if !params.isEmpty { envelope["params"] = params }
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    /// Call a method and return the whole reply object.
    private func reply(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let text = try XCTUnwrap(exchange(try requestLine(method, params, id: id)), "no reply for \(method)")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        XCTAssertEqual(object["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(object["id"] as? Int, id, "reply id must match the request id: \(text)")
        return object
    }

    /// Call a method and return its result, throwing RPCFailure on an error reply.
    @discardableResult
    private func call(_ method: String, _ params: [String: Any] = [:]) throws -> Any? {
        let object = try reply(method, params)
        if let error = object["error"] as? [String: Any] {
            throw RPCFailure(code: error["code"] as? Int ?? 0, message: error["message"] as? String ?? "", id: object["id"] as? Int)
        }
        let result = object["result"]
        return result is NSNull ? nil : result
    }

    private func windowParams(_ more: [String: Any] = [:]) -> [String: Any] {
        var params: [String: Any] = ["window": windowUUID!]
        params.merge(more) { _, new in new }
        return params
    }

    private func viewParams(_ viewID: Int, _ more: [String: Any] = [:]) -> [String: Any] {
        return windowParams(["viewID": viewID].merging(more) { _, new in new })
    }

    private func assertFailure(_ method: String, _ params: [String: Any], code: Int, file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try call(method, params)
            XCTFail("\(method) should have failed with \(code)", file: file, line: line)
        } catch let failure as RPCFailure {
            XCTAssertEqual(failure.code, code, "\(method): \(failure.message)", file: file, line: line)
        } catch {
            XCTFail("\(method): unexpected \(error)", file: file, line: line)
        }
    }

    // MARK: - Discovery

    func testHelloListsHostMethodsAndWindows() throws {
        let hello = try XCTUnwrap(try call("actionui.hello") as? [String: Any])
        XCTAssertEqual(hello["protocolVersion"] as? Int, 1)
        let host = try XCTUnwrap(hello["host"] as? [String: String])
        XCTAssertEqual(host["name"], "TestHost")
        XCTAssertEqual(host["version"], "0.1")
        let methods = try XCTUnwrap(hello["methods"] as? [String])
        XCTAssertEqual(methods, methods.sorted())
        for name in ["actionui.hello", "actionui.getValue", "actionui.setRows", "actionui.insertElement", "actionui.presentToast", "actionui.contentSizeLimits"] {
            XCTAssertTrue(methods.contains(name), "hello.methods must list \(name)")
        }
        XCTAssertEqual(hello["windows"] as? [String], [windowUUID])
        XCTAssertEqual(try call("actionui.listWindows") as? [String], [windowUUID])
    }

    func testGetElementInfo() throws {
        let info = try XCTUnwrap(try call("actionui.getElementInfo", windowParams()) as? [String: String])
        XCTAssertEqual(info["2"], "TextField")
        XCTAssertEqual(info["3"], "Toggle")
        XCTAssertEqual(info["5"], "Table")
        XCTAssertEqual(info["10"], "VStack")
        XCTAssertEqual(info["11"], "Text")
    }

    // MARK: - Values, strings, properties, state

    func testSetAndGetValueRoundTripAndEngineAgreement() throws {
        XCTAssertEqual(try call("actionui.setValue", viewParams(2, ["value": "Ada"])) as? Bool, true)
        XCTAssertEqual(try call("actionui.getValue", viewParams(2)) as? String, "Ada")
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2) as? String, "Ada")

        XCTAssertEqual(try call("actionui.setValue", viewParams(3, ["value": true])) as? Bool, true)
        XCTAssertEqual(try call("actionui.getValue", viewParams(3)) as? Bool, true)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 3) as? Bool, true)
    }

    func testValueStringAndNonJSONValuesComeBackAsNull() throws {
        XCTAssertEqual(try call("actionui.setValueString", viewParams(2, ["value": "typed text"])) as? Bool, true)
        XCTAssertEqual(try call("actionui.getValueString", viewParams(2)) as? String, "typed text")
        XCTAssertEqual(try call("actionui.getValue", viewParams(2)) as? String, "typed text")

        // A DatePicker holds a Date: no JSON form, so getValue is null and getValueString works.
        XCTAssertEqual(try call("actionui.setValueString", viewParams(6, ["value": "2026-09-02T10:00:00Z"])) as? Bool, true)
        XCTAssertNotNil(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 6) as? Date)
        XCTAssertNil(try call("actionui.getValue", viewParams(6)))
        XCTAssertTrue((try call("actionui.getValueString", viewParams(6)) as? String ?? "").hasPrefix("2026-09-02"))
    }

    func testViewPartIDSelectsATableColumnAndContentTypeIsHonored() throws {
        XCTAssertEqual(try call("actionui.setRows", viewParams(5, ["rows": [["a1", "b1"], ["a2", "b2"]]])) as? Bool, true)
        XCTAssertEqual(try call("actionui.selectRow", viewParams(5, ["index": 1])) as? [String], ["a2", "b2"])
        XCTAssertEqual(try call("actionui.getValue", viewParams(5)) as? [String], ["a2", "b2"])
        XCTAssertEqual(try call("actionui.getValue", viewParams(5, ["viewPartID": 1])) as? String, "a2")
        XCTAssertEqual(try call("actionui.getValue", viewParams(5, ["viewPartID": 2])) as? String, "b2")
        XCTAssertEqual(try call("actionui.getValueString", viewParams(5, ["viewPartID": 2])) as? String, "b2")

        XCTAssertEqual(try call("actionui.setValueString", viewParams(11, ["value": "# Hi", "contentType": "markdown"])) as? Bool, true)
        let markdown = try XCTUnwrap(try call("actionui.getValueString", viewParams(11, ["contentType": "plain"])) as? String)
        XCTAssertTrue(markdown.contains("Hi"), markdown)
    }

    func testPropertyRoundTrip() throws {
        XCTAssertEqual(try call("actionui.setProperty", viewParams(2, ["name": "disabled", "value": true])) as? Bool, true)
        XCTAssertEqual(try call("actionui.getProperty", viewParams(2, ["name": "disabled"])) as? Bool, true)
        XCTAssertEqual(ActionUIModel.shared.getElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "disabled") as? Bool, true)
    }

    func testStateCoercesJSONScalarsTowardTheStoredType() throws {
        // Engine-seeded states are Swift-native; JSON-decoded values are NSNumber/NSString.
        // A remote write must land, not report a spurious mismatch.
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 2, key: "flag", value: false)
        model.setElementState(windowUUID: windowUUID, viewID: 2, key: "ratio", value: 0.5)
        model.setElementState(windowUUID: windowUUID, viewID: 2, key: "count", value: 1)
        model.setElementState(windowUUID: windowUUID, viewID: 2, key: "name", value: "a")

        XCTAssertEqual(try call("actionui.setState", viewParams(2, ["key": "flag", "value": true])) as? Bool, true)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "flag") as? Bool, true)
        XCTAssertEqual(try call("actionui.setState", viewParams(2, ["key": "ratio", "value": 2])) as? Bool, true,
                       "a whole JSON number must be accepted by a Double state")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "ratio") as? Double, 2.0)
        XCTAssertEqual(try call("actionui.setState", viewParams(2, ["key": "count", "value": 7])) as? Bool, true)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "count") as? Int, 7)
        XCTAssertEqual(try call("actionui.setState", viewParams(2, ["key": "name", "value": "b"])) as? Bool, true)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "name") as? String, "b")

        assertFailure("actionui.setState", viewParams(2, ["key": "count", "value": 2.5]), code: 1003)
        assertFailure("actionui.setState", viewParams(2, ["key": "flag", "value": 1]), code: 1003)
        assertFailure("actionui.setState", viewParams(2, ["key": "name", "value": 3]), code: 1003)

        // A key created from the wire is stored Swift-native, so the engine's string setter and
        // string getter treat it exactly like a key created from Swift.
        XCTAssertEqual(try call("actionui.setState", viewParams(2, ["key": "remote", "value": 9])) as? Bool, true)
        XCTAssertTrue(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "remote") is Int)
        XCTAssertEqual(try call("actionui.getStateString", viewParams(2, ["key": "remote"])) as? String, "9")
        XCTAssertEqual(try call("actionui.setStateString", viewParams(2, ["key": "remote", "value": "10"])) as? Bool, true)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 2, key: "remote") as? Int, 10)
    }

    func testStateRoundTripAndTypeMismatchIs1003() throws {
        ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 2, key: "count", value: 5)
        assertFailure("actionui.setState", viewParams(2, ["key": "count", "value": "abc"]), code: 1003)
        XCTAssertEqual(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 2, key: "count") as? Int, 5)

        XCTAssertEqual(try call("actionui.setState", viewParams(2, ["key": "label", "value": "x"])) as? Bool, true)
        XCTAssertEqual(try call("actionui.getState", viewParams(2, ["key": "label"])) as? String, "x")
        XCTAssertEqual(try call("actionui.setStateString", viewParams(2, ["key": "count", "value": "9"])) as? Bool, true)
        XCTAssertEqual(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 2, key: "count") as? Int, 9)
        XCTAssertEqual(try call("actionui.getStateString", viewParams(2, ["key": "count"])) as? String, "9")
        XCTAssertNil(try call("actionui.getState", viewParams(2, ["key": "nope"])))
    }

    // MARK: - Rows and selection

    func testRowsAndSelection() throws {
        XCTAssertEqual(try call("actionui.setRows", viewParams(5, ["rows": [["a", "b"], ["c", "d"]]])) as? Bool, true)
        XCTAssertEqual(try call("actionui.getRows", viewParams(5)) as? [[String]], [["a", "b"], ["c", "d"]])
        XCTAssertEqual(try call("actionui.getColumnCount", viewParams(5)) as? Int, 2)
        XCTAssertEqual(try call("actionui.appendRows", viewParams(5, ["rows": [["e", "f"]]])) as? Bool, true)
        XCTAssertEqual((try call("actionui.getRows", viewParams(5)) as? [[String]])?.count, 3)

        XCTAssertEqual(try call("actionui.selectRow", viewParams(5, ["index": 1])) as? [String], ["c", "d"])
        XCTAssertEqual(try call("actionui.getValue", viewParams(5)) as? [String], ["c", "d"])
        XCTAssertEqual(try call("actionui.selectRowWithContent", viewParams(5, ["text": "e"])) as? Int, 2)
        XCTAssertEqual(try call("actionui.selectRowWithContent", viewParams(5, ["text": "zzz"])) as? Int, -1)
        XCTAssertEqual(try call("actionui.clearSelection", viewParams(5)) as? Bool, true)

        XCTAssertEqual(try call("actionui.clearRows", viewParams(5)) as? Bool, true)
        XCTAssertEqual((try call("actionui.getRows", viewParams(5)) as? [[String]])?.count ?? 0, 0)

        assertFailure("actionui.setRows", viewParams(5, ["rows": [["a", 1]]]), code: -32602)
        assertFailure("actionui.selectRow", viewParams(5, ["index": true]), code: -32602)
    }

    // MARK: - Structural mutation

    func testInsertAndRemoveElement() throws {
        let newID = try call("actionui.insertElement", windowParams([
            "parentID": 10,
            "element": ["id": 20, "type": "Text", "properties": ["text": "new"]],
            "position": ["kind": "prepend"],
        ])) as? Int
        XCTAssertEqual(newID, 20)
        XCTAssertTrue(ActionUIModel.shared.hasElement(windowUUID: windowUUID, viewID: 20))
        XCTAssertEqual((try call("actionui.getElementInfo", windowParams()) as? [String: String])?["20"], "Text")

        XCTAssertEqual(try call("actionui.removeElement", viewParams(20)) as? Bool, true)
        XCTAssertFalse(ActionUIModel.shared.hasElement(windowUUID: windowUUID, viewID: 20))

        assertFailure("actionui.removeElement", viewParams(99), code: 1002)
        assertFailure("actionui.insertElement", windowParams(["parentID": 2, "element": ["type": "Text"]]), code: 1003)
        assertFailure("actionui.insertElement", windowParams(["parentID": 10, "element": ["type": "Text"], "position": ["kind": "at", "index": true]]), code: -32602)
    }

    func testInsertElementWithExplicitContainerAndHelloWithTwoWindows() throws {
        let newID = try call("actionui.insertElement", windowParams([
            "parentID": 10,
            "element": ["id": 21, "type": "Text", "properties": ["text": "explicit"]],
            "container": "children",
        ])) as? Int
        XCTAssertEqual(newID, 21)
        assertFailure("actionui.insertElement", windowParams(["parentID": 10, "element": ["type": "Text"], "container": "rows"]), code: 1003)

        let second = "aaa-" + UUID().uuidString
        try loadFixtureWindow(uuid: second)
        let windows = try XCTUnwrap((try call("actionui.hello") as? [String: Any])?["windows"] as? [String])
        XCTAssertEqual(windows, [second, windowUUID].sorted())
    }

    func testInsertRowIntoGrid() throws {
        let ids = try call("actionui.insertRow", windowParams([
            "parentID": 7,
            "cells": [["id": 71, "type": "Text", "properties": ["text": "r1c0"]], ["id": 72, "type": "Text", "properties": ["text": "r1c1"]]],
            "position": ["kind": "at", "index": 0],
        ])) as? [Int]
        XCTAssertEqual(ids, [71, 72])
        XCTAssertTrue(ActionUIModel.shared.hasElement(windowUUID: windowUUID, viewID: 71))
        assertFailure("actionui.insertRow", windowParams(["parentID": 7, "cells": "not an array"]), code: -32602)
    }

    // MARK: - Presentation

    func testPresentationMethodsReachTheWindowModel() throws {
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])

        XCTAssertEqual(try call("actionui.presentToast", windowParams(["message": "Saved", "duration": 2])) as? Bool, true)
        XCTAssertNotNil(windowModel.windowToast)
        XCTAssertEqual(try call("actionui.dismissToast", windowParams()) as? Bool, true)

        XCTAssertEqual(try call("actionui.presentAlert", windowParams(["title": "Sure?", "buttons": [["title": "Cancel", "role": "cancel"], ["title": "Delete", "role": "destructive", "actionID": "delete.confirmed"]]])) as? Bool, true)
        XCTAssertNotNil(windowModel.windowDialog)
        XCTAssertEqual(try call("actionui.dismissDialog", windowParams()) as? Bool, true)
        XCTAssertNil(windowModel.windowDialog)
        XCTAssertEqual(try call("actionui.presentAlert", windowParams(["title": "Plain"])) as? Bool, true, "buttons are optional for an alert")
        XCTAssertEqual(try call("actionui.dismissDialog", windowParams()) as? Bool, true)
        assertFailure("actionui.presentConfirmationDialog", windowParams(["title": "No buttons"]), code: -32602)

        XCTAssertEqual(try call("actionui.presentModal", windowParams([
            "element": ["id": 200, "type": "VStack", "children": [["id": 201, "type": "Text", "properties": ["text": "modal"]]]],
            "style": "sheet",
        ])) as? Bool, true)
        XCTAssertNotNil(windowModel.windowModal)
        XCTAssertEqual(try call("actionui.dismissModal", windowParams()) as? Bool, true)
        XCTAssertNil(windowModel.windowModal)
        assertFailure("actionui.presentModal", windowParams(["element": ["type": "Text"], "style": "popover"]), code: -32602)
        assertFailure("actionui.presentModal", windowParams(["path": "relative.json"]), code: -32602)
        assertFailure("actionui.presentModal", windowParams(["path": "/nonexistent/modal.json"]), code: 1003)
    }

    func testContentSizeLimitsReturnsNullOrAnObject() throws {
        let result = try call("actionui.contentSizeLimits", windowParams())
        if let object = result as? [String: Any] {
            XCTAssertEqual(Set(object.keys), ["minWidth", "minHeight", "maxWidth", "maxHeight"])
        } else {
            XCTAssertNil(result)
        }
    }

    // MARK: - Errors and batches

    func testErrorCodes() throws {
        assertFailure("actionui.noSuchMethod", [:], code: -32601)
        assertFailure("actionui.getValue", ["window": "nope", "viewID": 2], code: 1001)
        assertFailure("actionui.getValue", viewParams(99), code: 1002)
        assertFailure("actionui.getValue", windowParams(), code: -32602)
        assertFailure("actionui.setValue", viewParams(2), code: -32602)

        let parseReply = try XCTUnwrap(exchange("{not json"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(parseReply.utf8)) as? [String: Any])
        XCTAssertTrue(object["id"] is NSNull)
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testBatchRunsInOrderAndOmitsNotifications() throws {
        let batch = "[" + [
            try requestLine("actionui.setValue", viewParams(2, ["value": "batched"]), id: 1),
            try requestLine("actionui.setValue", viewParams(3, ["value": false]), id: nil),   // notification
            try requestLine("actionui.getValue", viewParams(2), id: "two"),
            try requestLine("actionui.noSuchMethod", [:], id: 3),
        ].joined(separator: ",") + "]"
        let text = try XCTUnwrap(exchange(batch))
        let replies = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        XCTAssertEqual(replies.count, 3, "the notification gets no reply: \(text)")
        XCTAssertEqual(replies[0]["id"] as? Int, 1)
        XCTAssertEqual(replies[0]["result"] as? Bool, true)
        XCTAssertEqual(replies[1]["id"] as? String, "two")
        XCTAssertEqual(replies[1]["result"] as? String, "batched", "the getValue after the setValue in the same batch sees the new value")
        XCTAssertEqual(replies[2]["id"] as? Int, 3)
        XCTAssertEqual((replies[2]["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 3) as? Bool, false, "the notification was applied")
    }

    func testSingleNotificationIsAppliedAndNotAnswered() throws {
        _ = exchange(try requestLine("actionui.setValue", viewParams(2, ["value": "silent"]), id: nil), expectReply: false)
        XCTAssertEqual(try call("actionui.getValue", viewParams(2)) as? String, "silent")
    }

    func testBatchOfOnlyNotificationsGetsNoReply() throws {
        let batch = "[" + (try requestLine("actionui.setValue", viewParams(2, ["value": "quiet"]), id: nil)) + "]"
        _ = exchange(batch, expectReply: false)
        // Prove the batch was applied and the connection is still healthy with a normal call.
        XCTAssertEqual(try call("actionui.getValue", viewParams(2)) as? String, "quiet")
    }

    // MARK: - Extension methods

    func testHostMethodsRegisterAppearInHelloAndMapErrors() throws {
        server.register(method: "test.echo") { params in
            return ["echo": params["x"] ?? NSNull()]
        }
        server.register(method: "test.plainError") { _ in
            throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "host said no"])
        }
        server.register(method: "test.codedError") { _ in
            throw ActionUIRemoteError(code: 4242, message: "custom", data: ["why": "because"])
        }

        let methods = try XCTUnwrap((try call("actionui.hello") as? [String: Any])?["methods"] as? [String])
        XCTAssertTrue(methods.contains("test.echo"))

        XCTAssertEqual((try call("test.echo", ["x": 5]) as? [String: Any])?["echo"] as? Int, 5)
        assertFailure("test.plainError", [:], code: 1004)

        let coded = try reply("test.codedError")
        let error = try XCTUnwrap(coded["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 4242)
        XCTAssertEqual(error["message"] as? String, "custom")
        XCTAssertEqual((error["data"] as? [String: String])?["why"], "because")

        server.unregister(method: "test.echo")
        assertFailure("test.echo", [:], code: -32601)
    }

    func testMainThreadTimeoutYields1005AndLateResultIsDropped() throws {
        server.mainThreadTimeout = 0.2
        server.register(method: "test.sleep") { _ in
            Thread.sleep(forTimeInterval: 0.6)
            return "late"
        }
        assertFailure("test.sleep", [:], code: 1005)
        // The connection is still usable, and the next reply carries the next id, not the
        // abandoned request's late result.
        XCTAssertEqual(try call("actionui.listWindows") as? [String], [windowUUID])
    }

    // MARK: - Ordering across connections

    func testTwoConnectionsInterleaveWithoutMixingReplies() throws {
        let second = try TestSocketClient(path: socketPath, timeoutSeconds: 10)
        let first = self.client!
        let lines: [String] = try (0..<20).map { (i: Int) in
            try requestLine("actionui.setValue", viewParams(2, ["value": "v\(i)"]), id: i)
        }
        let done = expectation(description: "both clients done")
        done.expectedFulfillmentCount = 2
        let mismatches = ResultBox<Int>()
        mismatches.value = 0
        let lock = NSLock()
        for (index, client) in [first, second].enumerated() {
            DispatchQueue(label: "client.\(index)").async {
                for (i, line) in lines.enumerated() {
                    client.write(line + "\n")
                    guard let text = client.readLine(),
                          let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                          object["id"] as? Int == i else {
                        lock.lock(); mismatches.value! += 1; lock.unlock()
                        continue
                    }
                }
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 20)
        XCTAssertEqual(mismatches.value, 0, "every reply must carry the id of its own connection's request, in order")
    }
}

#endif
