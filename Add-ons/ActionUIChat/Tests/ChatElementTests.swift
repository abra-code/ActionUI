// Add-ons/ActionUIChat/Tests/ChatElementTests.swift
//
// Add-on-level tests of the Chat element glue over the ChatView component: ChatConfig's
// action-ID parsing and its derivation of the component flags (attachEnabled /
// emitsEntryEvents), validate() - the element's validateProperties witness - and the
// host-event -> actionHandler dispatch mapping (Chat.hostEventSink). The component's own
// behavior (store, views, transports, configuration parsing) is tested in the ChatView repo.

import XCTest
@testable import ActionUIChatCore
import ActionUI

private final class ElementTestLogger: ChatLogger {
    func log(_ message: String, _ level: ChatLogLevel) {}
}

/// For ChatConfig.validate, which is the ActionUI validateProperties witness and takes ActionUILogger.
private final class ValidateLogger: ActionUILogger {
    func log(_ message: String, _ level: LoggerLevel) {}
}

final class ChatConfigActionIDTests: XCTestCase {

    private func config(_ properties: [String: Any]) -> ChatConfig {
        ChatConfig(properties: properties, logger: ElementTestLogger())
    }

    func testActionIDsParse() {
        let parsed = config([
            "sendActionID": "chat.send",
            "stopActionID": "chat.stop",
            "messageActionID": "chat.message",
            "errorActionID": "chat.error",
            "approveToolActionID": "chat.tool.approve",
            "entryActionID": "chat.entry",
            "attachActionID": "chat.attach",
        ])
        XCTAssertEqual(parsed.sendActionID, "chat.send")
        XCTAssertEqual(parsed.stopActionID, "chat.stop")
        XCTAssertEqual(parsed.messageActionID, "chat.message")
        XCTAssertEqual(parsed.errorActionID, "chat.error")
        XCTAssertEqual(parsed.approveToolActionID, "chat.tool.approve")
        XCTAssertEqual(parsed.entryActionID, "chat.entry")
        XCTAssertEqual(parsed.attachActionID, "chat.attach")
    }

    func testActionIDsDefaultNil() {
        let parsed = config([:])
        XCTAssertNil(parsed.sendActionID)
        XCTAssertNil(parsed.stopActionID)
        XCTAssertNil(parsed.messageActionID)
        XCTAssertNil(parsed.errorActionID)
        XCTAssertNil(parsed.approveToolActionID)
        XCTAssertNil(parsed.entryActionID)
        XCTAssertNil(parsed.attachActionID)
    }

    // The component knows nothing about action IDs; the add-on maps their presence onto
    // the component's host-event flags.
    func testActionIDsDeriveComponentFlags() {
        let enabled = config(["entryActionID": "chat.entry", "attachActionID": "chat.attach"]).configuration
        XCTAssertTrue(enabled.emitsEntryEvents)
        XCTAssertTrue(enabled.attachEnabled)

        let disabled = config([:]).configuration
        XCTAssertFalse(disabled.emitsEntryEvents)
        XCTAssertFalse(disabled.attachEnabled)

        // An empty string does not enable an affordance.
        let empty = config(["entryActionID": "", "attachActionID": ""]).configuration
        XCTAssertFalse(empty.emitsEntryEvents)
        XCTAssertFalse(empty.attachEnabled)
    }

    // The visual keys flow through to the component configuration untouched.
    func testVisualKeysDelegateToConfiguration() {
        let parsed = config(["appearance": ["alignment": "dual"], "readOnly": true])
        XCTAssertEqual(parsed.configuration.alignment, .dual)
        XCTAssertTrue(parsed.configuration.readOnly)
    }
}

final class ChatConfigValidateTests: XCTestCase {

    private func validate(_ properties: [String: Any]) -> [String: Any] {
        ChatConfig.validate(properties, ValidateLogger())
    }

    func testObjectKeysMustBeObjects() {
        XCTAssertNil(validate(["features": "yes"])["features"], "a non-object features is dropped")
        XCTAssertNil(validate(["appearance": 7])["appearance"], "a non-object appearance is dropped")
    }

    func testValidateDropsUnknownFeatureKeysAndNonBoolValues() {
        let validated = validate(["features": ["reactions": true, "bogus": true, "editing": "yes"]])
        let features = validated["features"] as? [String: Any]
        XCTAssertEqual(features?["reactions"] as? Bool, true, "a known Bool feature survives")
        XCTAssertNil(features?["bogus"], "an unknown feature key is dropped")
        XCTAssertNil(features?["editing"], "a non-Bool feature value is dropped")
    }

    func testValidateDropsUnknownSurfaceKeysAndModes() {
        let validated = validate([
            "surfaces": ["bogus": "inline", "thoughts": "sideways", "toolCalls": "collapsed"],
        ])
        let surfaces = validated["surfaces"] as? [String: Any]
        XCTAssertNil(surfaces?["bogus"], "unknown surface keys must be dropped")
        XCTAssertNil(surfaces?["thoughts"], "unknown surface modes must be dropped")
        XCTAssertEqual(surfaces?["toolCalls"] as? String, "collapsed")
    }

    func testActionIDsMustBeStrings() {
        XCTAssertNil(validate(["attachActionID": 42])["attachActionID"], "a non-String attachActionID is dropped")
        XCTAssertEqual(validate(["attachActionID": "chat.attach"])["attachActionID"] as? String, "chat.attach")
        XCTAssertNil(validate(["sendActionID": 1])["sendActionID"])
    }

    func testReadOnlyMustBeBool() {
        XCTAssertNil(validate(["readOnly": "yes"])["readOnly"])
        XCTAssertEqual(validate(["readOnly": true])["readOnly"] as? Bool, true)
    }
}

@MainActor
final class ChatHostEventDispatchTests: XCTestCase {

    /// Collects (actionID, viewID, context) triples from a registered ActionUI handler.
    private final class Captured: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(actionID: String, viewID: Int, context: Any?)] = []
        func add(_ actionID: String, _ viewID: Int, _ context: Any?) {
            lock.withLock { calls.append((actionID, viewID, context)) }
        }
        var all: [(actionID: String, viewID: Int, context: Any?)] {
            lock.withLock { calls }
        }
    }

    func testSinkDispatchesConfiguredActionIDsThroughActionHandler() {
        let captured = Captured()
        let entryID = "test.dispatch.entry.\(UUID().uuidString)"
        let sendID = "test.dispatch.send.\(UUID().uuidString)"
        for actionID in [entryID, sendID] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { id, _, viewID, _, context in
                captured.add(id, viewID, context)
            }
        }
        defer {
            ActionUIModel.shared.unregisterActionHandler(for: entryID)
            ActionUIModel.shared.unregisterActionHandler(for: sendID)
        }

        let config = ChatConfig(properties: ["entryActionID": entryID, "sendActionID": sendID],
                                logger: ElementTestLogger())
        let sink = Chat.hostEventSink(config: config, windowUUID: "w", elementID: 7)

        sink(.send)
        sink(.entry(json: #"{"sequence":1}"#))
        sink(.stop)      // no stopActionID configured: must not dispatch
        sink(.error)     // no errorActionID configured: must not dispatch

        let calls = captured.all
        XCTAssertEqual(calls.count, 2, "only configured action IDs dispatch")
        XCTAssertEqual(calls[0].actionID, sendID)
        XCTAssertNil(calls[0].context, "fire-and-forget events carry no context")
        XCTAssertEqual(calls[0].viewID, 7)
        XCTAssertEqual(calls[1].actionID, entryID)
        XCTAssertEqual(calls[1].context as? String, #"{"sequence":1}"#, "the entry event carries its JSON envelope as the action context")
    }
}
