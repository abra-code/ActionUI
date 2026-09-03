// ActionUIRemoteTests/JSONRPCTests.swift
//
// Pins the JSON-RPC 2.0 envelope codec: what is accepted, what is rejected with which code,
// what a rejection still carries (id, notification flag), and the exact reply shapes.
// Every language client depends on these staying stable.

import XCTest
@testable import ActionUIRemote

final class JSONRPCTests: XCTestCase {

    private func decode(_ text: String) throws -> JSONRPCIncoming {
        try JSONRPC.decode(line: Data(text.utf8))
    }

    /// Decode a line that must be a single, valid request.
    private func single(_ text: String) throws -> JSONRPCRequest {
        guard case .single(let outcome) = try decode(text) else {
            XCTFail("expected a single request")
            throw ActionUIRemoteError(code: 0, message: "not single")
        }
        return try outcome.get()
    }

    /// Decode a line that must be a single object rejected during validation.
    private func rejected(_ text: String) throws -> JSONRPCRejection {
        guard case .single(let outcome) = try decode(text), case .failure(let rejection) = outcome else {
            XCTFail("expected a rejected single request: \(text)")
            throw ActionUIRemoteError(code: 0, message: "not rejected")
        }
        return rejection
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func code(of error: Error) -> Int? {
        (error as? ActionUIRemoteError)?.code
    }

    // MARK: - Decoding: valid inputs

    func testValidRequestWithIntegerID() throws {
        let request = try single(#"{"jsonrpc":"2.0","id":7,"method":"actionui.getValue","params":{"window":"W","viewID":2}}"#)
        XCTAssertEqual(request.id as? Int, 7)
        XCTAssertEqual(request.method, "actionui.getValue")
        XCTAssertEqual(request.params["window"] as? String, "W")
        XCTAssertEqual(request.params["viewID"] as? Int, 2)
        XCTAssertFalse(request.isNotification)
    }

    func testValidRequestWithStringID() throws {
        let request = try single(#"{"jsonrpc":"2.0","id":"req-a","method":"actionui.hello"}"#)
        XCTAssertEqual(request.id as? String, "req-a")
        XCTAssertTrue(request.params.isEmpty, "absent params decode as an empty dictionary")
    }

    func testFractionalAndLargeIDsSurviveVerbatim() throws {
        let fractional = try single(#"{"jsonrpc":"2.0","id":1.5,"method":"m"}"#)
        XCTAssertEqual(fractional.id as? Double, 1.5)
        let reply = try object(JSONRPC.encodeResult(id: fractional.id, result: nil))
        XCTAssertEqual(reply["id"] as? Double, 1.5)

        let large = try single(#"{"jsonrpc":"2.0","id":9007199254740993,"method":"m"}"#)
        XCTAssertEqual(large.id as? Int64, 9007199254740993)
        let largeReply = String(decoding: JSONRPC.encodeResult(id: large.id, result: nil), as: UTF8.self)
        XCTAssertTrue(largeReply.contains("\"id\":9007199254740993"), largeReply)
    }

    func testNotificationHasNoID() throws {
        let request = try single(#"{"jsonrpc":"2.0","method":"actionui.setValue","params":{"window":"W","viewID":2,"value":"x"}}"#)
        XCTAssertNil(request.id)
        XCTAssertTrue(request.isNotification)
    }

    func testNullIDAndNullParamsAreTreatedAsAbsent() throws {
        let request = try single(#"{"jsonrpc":"2.0","id":null,"method":"m","params":null}"#)
        XCTAssertTrue(request.isNotification)
        XCTAssertTrue(request.params.isEmpty)
    }

    func testBatchKeepsOrderAndPerEntryErrors() throws {
        let text = #"[{"jsonrpc":"2.0","id":1,"method":"a"},"not an object",{"jsonrpc":"2.0","method":"b"},{"jsonrpc":"1.0","id":3,"method":"c"}]"#
        guard case .batch(let entries) = try decode(text) else { return XCTFail("expected a batch") }
        XCTAssertEqual(entries.count, 4)
        if case .success(let first) = entries[0] {
            XCTAssertEqual(first.id as? Int, 1)
            XCTAssertEqual(first.method, "a")
        } else { XCTFail("entry 0 should decode") }
        if case .failure(let second) = entries[1] {
            XCTAssertEqual(second.error.code, ActionUIRemoteError.invalidRequest)
            XCTAssertNil(second.id)
            XCTAssertTrue(second.wantsReply, "a non-object entry gets an error reply with a null id")
        } else { XCTFail("entry 1 should be invalid") }
        if case .success(let third) = entries[2] {
            XCTAssertTrue(third.isNotification)
        } else { XCTFail("entry 2 should decode as a notification") }
        if case .failure(let fourth) = entries[3] {
            XCTAssertEqual(fourth.error.code, ActionUIRemoteError.invalidRequest)
            XCTAssertEqual(fourth.id as? Int, 3, "the id was detectable and must come back on the error reply")
        } else { XCTFail("entry 3 has the wrong jsonrpc version") }
    }

    // MARK: - Decoding: rejected lines (nothing recoverable, null-id reply)

    func testParseError() {
        XCTAssertThrowsError(try decode("{not json")) { XCTAssertEqual(self.code(of: $0), ActionUIRemoteError.parseError) }
        XCTAssertThrowsError(try decode("")) { XCTAssertEqual(self.code(of: $0), ActionUIRemoteError.parseError) }
    }

    func testUnrecoverableShapesThrowInvalidRequest() {
        // A bare scalar is well-formed JSON but not a request.
        XCTAssertThrowsError(try decode("42")) { XCTAssertEqual(self.code(of: $0), ActionUIRemoteError.invalidRequest) }
        XCTAssertThrowsError(try decode("\"text\"")) { XCTAssertEqual(self.code(of: $0), ActionUIRemoteError.invalidRequest) }
        XCTAssertThrowsError(try decode("[]")) { XCTAssertEqual(self.code(of: $0), ActionUIRemoteError.invalidRequest) }
    }

    func testOversizedBatchIsRejectedBeforeAnyEntryIsLookedAt() {
        let entry = #"{"jsonrpc":"2.0","method":"m"}"#
        let tooMany = "[" + Array(repeating: entry, count: JSONRPC.maxBatchEntries + 1).joined(separator: ",") + "]"
        XCTAssertThrowsError(try decode(tooMany)) { error in
            XCTAssertEqual(self.code(of: error), ActionUIRemoteError.invalidRequest)
            XCTAssertTrue((error as? ActionUIRemoteError)?.message.contains("exceeds the limit") ?? false)
        }
        let atLimit = "[" + Array(repeating: entry, count: JSONRPC.maxBatchEntries).joined(separator: ",") + "]"
        XCTAssertNoThrow(try decode(atLimit))
    }

    // MARK: - Decoding: rejected objects (id and notification flag preserved)

    func testInvalidRequestObjectsKeepTheirID() throws {
        // Missing or wrong version.
        var rejection = try rejected(#"{"id":1,"method":"m"}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidRequest)
        XCTAssertEqual(rejection.id as? Int, 1)
        XCTAssertTrue(rejection.wantsReply)

        rejection = try rejected(#"{"jsonrpc":"1.0","id":"x","method":"m"}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidRequest)
        XCTAssertEqual(rejection.id as? String, "x")

        rejection = try rejected(#"{"jsonrpc":2.0,"id":1,"method":"m"}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidRequest)

        // Method missing, empty, or not a string.
        for text in [#"{"jsonrpc":"2.0","id":5}"#, #"{"jsonrpc":"2.0","id":5,"method":""}"#, #"{"jsonrpc":"2.0","id":5,"method":5}"#] {
            rejection = try rejected(text)
            XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidRequest, text)
            XCTAssertEqual(rejection.id as? Int, 5, text)
        }
    }

    func testInvalidRequestWithoutIDStillWantsANullIDReply() throws {
        // The specification's own example: {"jsonrpc":"2.0","method":1} is answered with a null id.
        let rejection = try rejected(#"{"jsonrpc":"2.0","method":1}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidRequest)
        XCTAssertNil(rejection.id)
        XCTAssertTrue(rejection.isNotification)
        XCTAssertTrue(rejection.wantsReply)
    }

    func testForbiddenIDTypesAreRejectedWithNullID() throws {
        for text in [#"{"jsonrpc":"2.0","id":true,"method":"m"}"#, #"{"jsonrpc":"2.0","id":[1],"method":"m"}"#, #"{"jsonrpc":"2.0","id":{"k":1},"method":"m"}"#] {
            let rejection = try rejected(text)
            XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidRequest, text)
            XCTAssertNil(rejection.id, "an undetectable id is reported as null: \(text)")
            XCTAssertFalse(rejection.isNotification, text)
            XCTAssertTrue(rejection.wantsReply, text)
        }
    }

    func testPositionalParamsRejectedWithInvalidParamsAndIDKept() throws {
        var rejection = try rejected(#"{"jsonrpc":"2.0","id":7,"method":"m","params":[1,2]}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidParams)
        XCTAssertEqual(rejection.id as? Int, 7, "the client matches the error to request 7 by id")
        XCTAssertTrue(rejection.wantsReply)

        rejection = try rejected(#"{"jsonrpc":"2.0","id":7,"method":"m","params":"x"}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidParams)
    }

    func testInvalidParamsOnANotificationIsNotAnswered() throws {
        let rejection = try rejected(#"{"jsonrpc":"2.0","method":"m","params":[1,2]}"#)
        XCTAssertEqual(rejection.error.code, ActionUIRemoteError.invalidParams)
        XCTAssertTrue(rejection.isNotification)
        XCTAssertFalse(rejection.wantsReply, "a structurally valid notification never gets a reply, even a failing one")
    }

    // MARK: - Encoding

    func testEncodeResultShapeAndIDPreservation() throws {
        let intReply = try object(JSONRPC.encodeResult(id: NSNumber(value: 7), result: ["a", "b"]))
        XCTAssertEqual(intReply["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(intReply["id"] as? Int, 7)
        XCTAssertEqual(intReply["result"] as? [String], ["a", "b"])
        XCTAssertNil(intReply["error"])

        let stringReply = try object(JSONRPC.encodeResult(id: "req-a", result: true))
        XCTAssertEqual(stringReply["id"] as? String, "req-a")
        XCTAssertEqual(stringReply["result"] as? Bool, true)
    }

    func testEncodeResultNilBecomesNull() throws {
        let reply = try object(JSONRPC.encodeResult(id: NSNumber(value: 1), result: nil))
        XCTAssertTrue(reply["result"] is NSNull)
        let text = String(decoding: JSONRPC.encodeResult(id: NSNumber(value: 1), result: nil), as: UTF8.self)
        XCTAssertTrue(text.contains("\"result\":null"), text)
    }

    func testEncodeResultStaysOnOneLine() throws {
        // The reply is one line of JSON with no embedded raw newlines, even for multi-line strings.
        let data = JSONRPC.encodeResult(id: NSNumber(value: 1), result: "line one\nline two")
        XCTAssertFalse(data.contains(UInt8(ascii: "\n")))
        let reply = try object(data)
        XCTAssertEqual(reply["result"] as? String, "line one\nline two")
    }

    func testEncodeResultWithUnencodableValueBecomesInternalError() throws {
        let reply = try object(JSONRPC.encodeResult(id: NSNumber(value: 3), result: Date()))
        XCTAssertEqual(reply["id"] as? Int, 3)
        let error = try XCTUnwrap(reply["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, ActionUIRemoteError.internalError)
        XCTAssertTrue((error["message"] as? String ?? "").contains("Date"))
        XCTAssertNil(reply["result"])
    }

    func testEncodeWithUnencodableIDNeverCrashesAndReportsNullID() throws {
        // Not reachable from a client (decode constrains ids), but the public API must not be able
        // to raise the ObjC exception JSONSerialization throws for an invalid object.
        let resultReply = try object(JSONRPC.encodeResult(id: Date(), result: "ok"))
        XCTAssertTrue(resultReply["id"] is NSNull)
        XCTAssertNotNil(resultReply["error"], "the unencodable envelope is reported as an internal error")

        let errorReply = try object(JSONRPC.encodeError(id: Date(), error: ActionUIRemoteError(code: 1001, message: "m")))
        XCTAssertTrue(errorReply["id"] is NSNull)
        XCTAssertEqual((errorReply["error"] as? [String: Any])?["code"] as? Int, 1001)
    }

    func testEncodeErrorShapeWithAndWithoutData() throws {
        let plain = try object(JSONRPC.encodeError(id: "x", error: ActionUIRemoteError(code: 1001, message: "Unknown window")))
        XCTAssertEqual(plain["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(plain["id"] as? String, "x")
        let error = try XCTUnwrap(plain["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, 1001)
        XCTAssertEqual(error["message"] as? String, "Unknown window")
        XCTAssertNil(error["data"])
        XCTAssertNil(plain["result"])

        let withData = try object(JSONRPC.encodeError(id: nil, error: ActionUIRemoteError(code: 1004, message: "refused", data: ["reason": "closed"])))
        XCTAssertTrue(withData["id"] is NSNull, "an error for an unidentifiable request carries a null id")
        let dataField = try XCTUnwrap((withData["error"] as? [String: Any])?["data"] as? [String: Any])
        XCTAssertEqual(dataField["reason"] as? String, "closed")

        // Scalar data is fine; non-JSON data is dropped rather than breaking the reply.
        let scalarData = try object(JSONRPC.encodeError(id: nil, error: ActionUIRemoteError(code: 1, message: "m", data: 42)))
        XCTAssertEqual((scalarData["error"] as? [String: Any])?["data"] as? Int, 42)
        let badData = try object(JSONRPC.encodeError(id: nil, error: ActionUIRemoteError(code: 1, message: "m", data: Date())))
        XCTAssertNil((badData["error"] as? [String: Any])?["data"])
    }

    func testEncodeBatch() throws {
        let replies = [
            JSONRPC.encodeResult(id: NSNumber(value: 1), result: true),
            JSONRPC.encodeError(id: NSNumber(value: 2), error: ActionUIRemoteError(code: -32601, message: "Method not found")),
        ]
        let batch = try XCTUnwrap(JSONRPC.encodeBatch(replies))
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch) as? [[String: Any]])
        XCTAssertEqual(array.count, 2)
        XCTAssertEqual(array[0]["id"] as? Int, 1)
        XCTAssertEqual(array[1]["id"] as? Int, 2)
        XCTAssertNotNil(array[1]["error"])
        XCTAssertNil(JSONRPC.encodeBatch([]), "a batch of only notifications produces no reply at all")
    }

    func testErrorCodesAreTheDocumentedValues() {
        XCTAssertEqual(ActionUIRemoteError.parseError, -32700)
        XCTAssertEqual(ActionUIRemoteError.invalidRequest, -32600)
        XCTAssertEqual(ActionUIRemoteError.methodNotFound, -32601)
        XCTAssertEqual(ActionUIRemoteError.invalidParams, -32602)
        XCTAssertEqual(ActionUIRemoteError.internalError, -32603)
        XCTAssertEqual(ActionUIRemoteError.unknownWindow, 1001)
        XCTAssertEqual(ActionUIRemoteError.unknownView, 1002)
        XCTAssertEqual(ActionUIRemoteError.engineFailure, 1003)
        XCTAssertEqual(ActionUIRemoteError.hostRefused, 1004)
        XCTAssertEqual(ActionUIRemoteError.mainThreadUnavailable, 1005)
        XCTAssertEqual(ActionUIRemoteError.invalidParams("missing \"window\"").description, "[-32602] missing \"window\"")
    }
}
