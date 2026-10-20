// Add-ons/ActionUIChat/Tests/ChatElementTests.swift
//
// Add-on-level tests of the Chat element glue over the ChatView component: ChatConfig's
// action-ID parsing and its derivation of the component flags (attachEnabled /
// emitsEntryEvents), its reading of the raw properties, and the
// host-event -> actionHandler dispatch mapping (Chat.hostEventSink). The component's own
// behavior (store, views, transports, configuration parsing) is tested in the ChatView repo.

import XCTest
@testable import ActionUIChatCore
import ActionUI

private final class ElementTestLogger: ChatLogger {
    func log(_ message: String, _ level: ChatLogLevel) {}
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
            "resumeCheckpointActionID": "chat.checkpoint",
            "attachActionID": "chat.attach",
        ])
        XCTAssertEqual(parsed.sendActionID, "chat.send")
        XCTAssertEqual(parsed.stopActionID, "chat.stop")
        XCTAssertEqual(parsed.messageActionID, "chat.message")
        XCTAssertEqual(parsed.errorActionID, "chat.error")
        XCTAssertEqual(parsed.approveToolActionID, "chat.tool.approve")
        XCTAssertEqual(parsed.entryActionID, "chat.entry")
        XCTAssertEqual(parsed.resumeCheckpointActionID, "chat.checkpoint")
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
        XCTAssertNil(parsed.resumeCheckpointActionID)
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

        // The checkpoint ID is NOT an entry-event trigger. If this ever flips to true, a host that
        // wired only the cursor starts storing a checkpoint at afterSeq=N against a transcript it
        // never stored, and the next attach resumes past everything before N - silently, since the
        // component never sees what the host restored.
        let cursorOnly = config(["resumeCheckpointActionID": "chat.checkpoint"]).configuration
        XCTAssertFalse(cursorOnly.emitsEntryEvents)
    }

    // The visual keys flow through to the component configuration untouched.
    func testVisualKeysDelegateToConfiguration() {
        let parsed = config(["appearance": ["alignment": "dual"], "readOnly": true])
        XCTAssertEqual(parsed.configuration.alignment, .dual)
        XCTAssertTrue(parsed.configuration.readOnly)
        XCTAssertFalse(config(["showFindBar": false]).configuration.showFindBar)
        XCTAssertTrue(config([:]).configuration.showFindBar)
        XCTAssertEqual(config(["remoteImages": "on-click"]).configuration.remoteImages, .onClick)
        XCTAssertEqual(config([:]).configuration.remoteImages, .automatic)
    }
}

final class ChatConfigPropertyReadingTests: XCTestCase {

    private func config(_ properties: [String: Any]) -> ChatConfig {
        ChatConfig(properties: properties, logger: ElementTestLogger())
    }

    func testObjectKeysMustBeObjects() {
        XCTAssertFalse(config(["features": "yes"]).configuration.features.reactions, "a non-object features is ignored")
        XCTAssertEqual(config(["appearance": 7]).configuration.alignment, .single, "a non-object appearance is ignored")
    }

    func testUnknownFeatureKeysAndNonBoolValuesAreIgnored() {
        let features = config(["features": ["reactions": true, "bogus": true, "editing": "yes"]]).configuration.features
        XCTAssertTrue(features.reactions, "a known Bool feature is read")
        XCTAssertFalse(features.editing, "a non-Bool feature value is ignored")
    }

    func testUnknownSurfaceModesAreIgnored() {
        let surfaces = config([
            "surfaces": ["bogus": "inline", "thoughts": "sideways", "toolCalls": "collapsed"],
        ]).configuration.surfaces
        XCTAssertEqual(surfaces.thoughts, .collapsed, "an unknown surface mode keeps the default")
        XCTAssertEqual(surfaces.toolCalls, .collapsed)
    }

    func testActionIDsMustBeStrings() {
        XCTAssertNil(config(["attachActionID": 42]).attachActionID, "a non-String attachActionID is ignored")
        XCTAssertEqual(config(["attachActionID": "chat.attach"]).attachActionID, "chat.attach")
        XCTAssertNil(config(["sendActionID": 1]).sendActionID)
        XCTAssertNil(config(["entryActionID": 1]).entryActionID)
        XCTAssertNil(config(["resumeCheckpointActionID": 7]).resumeCheckpointActionID,
                     "a non-String resumeCheckpointActionID is ignored")
        XCTAssertEqual(config(["resumeCheckpointActionID": "chat.checkpoint"]).resumeCheckpointActionID,
                       "chat.checkpoint")
    }

    // A checkpoint action ID without an entry action ID is inert by contract: the component only
    // offers a resume cursor while emitsEntryEvents is true, and that derives from entryActionID.
    func testResumeCheckpointNeedsEntryActionID() {
        XCTAssertFalse(config(["resumeCheckpointActionID": "chat.checkpoint"]).configuration.emitsEntryEvents)
        XCTAssertTrue(config(["resumeCheckpointActionID": "chat.checkpoint", "entryActionID": "chat.entry"])
                        .configuration.emitsEntryEvents)
    }

    func testReadOnlyMustBeBool() {
        XCTAssertFalse(config(["readOnly": "yes"]).configuration.readOnly)
        XCTAssertTrue(config(["readOnly": true]).configuration.readOnly)
    }

    func testShowFindBarMustBeBoolAndFalseIsRead() {
        XCTAssertTrue(config(["showFindBar": "yes"]).configuration.showFindBar, "a non-Bool keeps the default")
        XCTAssertFalse(config(["showFindBar": false]).configuration.showFindBar)
        XCTAssertTrue(config(["showFindBar": true]).configuration.showFindBar)
    }

    func testRemoteImagesMustBeAKnownPolicy() {
        XCTAssertEqual(config(["remoteImages": "on-click"]).configuration.remoteImages, .onClick)
        XCTAssertEqual(config(["remoteImages": "never"]).configuration.remoteImages, .never)
        XCTAssertEqual(config(["remoteImages": "automatic"]).configuration.remoteImages, .automatic)
        // A typo fails closed rather than meaning automatic.
        XCTAssertEqual(config(["remoteImages": "onClick"]).configuration.remoteImages, .onClick)
        XCTAssertEqual(config(["remoteImages": true]).configuration.remoteImages, .onClick)
        XCTAssertEqual(config([:]).configuration.remoteImages, .automatic, "absent is automatic")
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
        let checkpointID = "test.dispatch.checkpoint.\(UUID().uuidString)"
        for actionID in [entryID, sendID, checkpointID] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { id, _, viewID, _, context in
                captured.add(id, viewID, context)
            }
        }
        defer {
            ActionUIModel.shared.unregisterActionHandler(for: entryID)
            ActionUIModel.shared.unregisterActionHandler(for: sendID)
            ActionUIModel.shared.unregisterActionHandler(for: checkpointID)
        }

        let config = ChatConfig(properties: ["entryActionID": entryID, "sendActionID": sendID,
                                             "resumeCheckpointActionID": checkpointID],
                                logger: ElementTestLogger())
        let sink = Chat.hostEventSink(config: config, windowUUID: "w", elementID: 7)

        sink(.send)
        sink(.entry(json: #"{"sequence":1}"#))
        sink(.resumeCheckpoint(json: #"{"afterSeq":7,"sessionId":"s-1"}"#))
        sink(.stop)      // no stopActionID configured: must not dispatch
        sink(.error)     // no errorActionID configured: must not dispatch

        let calls = captured.all
        XCTAssertEqual(calls.count, 3, "only configured action IDs dispatch")
        XCTAssertEqual(calls[0].actionID, sendID)
        XCTAssertNil(calls[0].context, "fire-and-forget events carry no context")
        XCTAssertEqual(calls[0].viewID, 7)
        XCTAssertEqual(calls[1].actionID, entryID)
        XCTAssertEqual(calls[1].context as? String, #"{"sequence":1}"#, "the entry event carries its JSON envelope as the action context")
        // The other half of the persistence contract. Asserted separately from .entry because the
        // two are the only context-carrying cases: a refactor that dropped the `context = json`
        // assignment here would still dispatch the action, just with an empty cursor, and the host
        // would silently persist nothing resumable.
        XCTAssertEqual(calls[2].actionID, checkpointID)
        XCTAssertEqual(calls[2].context as? String, #"{"afterSeq":7,"sessionId":"s-1"}"#,
                       "the checkpoint event carries its cursor JSON as the action context")
    }
}

/// ChatConfig reads the properties the element's buildView receives, as given.
final class ChatConfigRawPropertiesTests: XCTestCase {

    private func config(_ properties: [String: Any]) -> ChatConfig {
        ChatConfig(properties: properties, logger: ElementTestLogger())
    }

    func testUnknownRemoteImagesFailsClosed() {
        // An unknown value fails closed to "on-click".
        XCTAssertEqual(config(["remoteImages": "onclick"]).configuration.remoteImages, .onClick)
        XCTAssertEqual(config(["remoteImages": false]).configuration.remoteImages, .onClick)
        XCTAssertEqual(config(["remoteImages": "never"]).configuration.remoteImages, .never)
        XCTAssertEqual(config([:]).configuration.remoteImages, .automatic)
    }

    func testWronglyTypedActionIDsAreIgnored() {
        let parsed = config(["sendActionID": 5, "entryActionID": true, "attachActionID": ["x"]])
        XCTAssertNil(parsed.sendActionID)
        XCTAssertNil(parsed.entryActionID)
        XCTAssertNil(parsed.attachActionID)
        XCTAssertFalse(parsed.configuration.emitsEntryEvents)
        XCTAssertFalse(parsed.configuration.attachEnabled)
    }
}
