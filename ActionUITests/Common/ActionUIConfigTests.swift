// Tests/Common/ActionUIConfigTests.swift
/*
 ActionUIConfigTests.swift

 Tests for the element-level NON-VISUAL "config" block (sibling of "properties"):
 decoding/encoding on ActionUIElement, verbatim population of ViewModel.config on load
 (core stores config raw - the element's buildView is the one consumer and checks what
 it reads; there is no central config validation), and the
 getElementConfig/setElementConfig runtime APIs including the canonical
 load-then-inject-before-first-render flow.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIConfigTests: XCTestCase {
    private var logger: XCTestLogger!
    private let windowUUID = "config-test-window"

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.resetForTesting()
    }

    override func tearDown() async throws {
        ActionUIModel.resetForTesting()
        logger = nil
        try await super.tearDown()
    }

    // MARK: - Element decoding / encoding

    func testDecodingConfigBlock() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Text",
            "config": { "mode": "demo", "transport": { "command": ["echo", "hi"], "cwd": "~" } },
            "properties": { "text": "Hello" }
        }
        """
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(jsonString.utf8))

        XCTAssertEqual(element.config["mode"] as? String, "demo")
        let transport = try XCTUnwrap(element.config["transport"] as? [String: Any])
        XCTAssertEqual(transport["command"] as? [String], ["echo", "hi"])
        XCTAssertEqual(transport["cwd"] as? String, "~")
        XCTAssertEqual(element.properties["text"] as? String, "Hello", "properties must be unaffected")
    }

    func testMissingConfigDecodesEmpty() throws {
        let jsonString = """
        { "id": 1, "type": "Text", "properties": { "text": "Hello" } }
        """
        let element = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(jsonString.utf8))
        XCTAssertTrue(element.config.isEmpty)
    }

    func testConfigRoundTripsThroughEncoding() throws {
        let jsonString = """
        { "id": 1, "type": "Text", "config": { "mode": "demo" }, "properties": {} }
        """
        let original = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data(jsonString.utf8))
        let encoded = try JSONEncoder(logger: logger).encode(original)
        let decoded = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: encoded)

        XCTAssertEqual(decoded.config["mode"] as? String, "demo")
        XCTAssertEqual(original, decoded, "Equatable must include config")
    }

    func testConfigDifferenceBreaksEquality() throws {
        let a = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data("""
        { "id": 1, "type": "Text", "config": { "mode": "a" } }
        """.utf8))
        let b = try JSONDecoder(logger: logger).decode(ActionUIElement.self, from: Data("""
        { "id": 1, "type": "Text", "config": { "mode": "b" } }
        """.utf8))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Load populates the live copy verbatim

    func testLoadPopulatesViewModelConfigVerbatim() throws {
        // Core does not interpret config: whatever the document carries reaches the
        // ViewModel unchanged, and the element's buildView checks what it reads.
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "config": ["anything": "goes", "transport": ["command": ["agent"]]],
            "properties": ["text": "Hello"],
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)

        let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
        XCTAssertEqual(viewModel.config["anything"] as? String, "goes")
        let transport = try XCTUnwrap(viewModel.config["transport"] as? [String: Any])
        XCTAssertEqual(transport["command"] as? [String], ["agent"])
    }

    // MARK: - Runtime get/set

    func testGetAndSetElementConfig() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "config": ["mode": "demo"],
            "properties": ["text": "Hello"],
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)

        XCTAssertEqual(model.getElementConfig(windowUUID: windowUUID, viewID: 1, key: "mode") as? String, "demo")

        model.setElementConfig(windowUUID: windowUUID, viewID: 1, key: "transport",
                               value: ["command": ["echo"], "cwd": "/tmp"])
        let transport = try XCTUnwrap(model.getElementConfig(windowUUID: windowUUID, viewID: 1, key: "transport") as? [String: Any])
        XCTAssertEqual(transport["command"] as? [String], ["echo"])
        XCTAssertEqual(model.getElementConfig(windowUUID: windowUUID, viewID: 1, key: "mode") as? String, "demo",
                       "setting one key must preserve the others")
    }

    // The config-origin bit (used by add-ons for security decisions, e.g. ActionUIChat's
    // transport-command policy): document-parsed keys are NOT host-injected; a runtime
    // setElementConfig marks its key as host-injected.
    func testConfigOriginDistinguishesDocumentFromHostInjection() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "config": ["mode": "demo", "transport": ["command": ["from-document"]]],
            "properties": ["text": "Hello"],
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[1])

        XCTAssertFalse(viewModel.isConfigHostInjected("transport"), "a document config key is not host-injected")
        XCTAssertFalse(viewModel.isConfigHostInjected("mode"))

        model.setElementConfig(windowUUID: windowUUID, viewID: 1, key: "transport", value: ["command": ["from-host"]])
        XCTAssertTrue(viewModel.isConfigHostInjected("transport"), "a setElementConfig key becomes host-injected")
        XCTAssertFalse(viewModel.isConfigHostInjected("mode"), "an untouched document key stays document-origin")
    }

    func testGetElementConfigMissingKeyReturnsNil() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "properties": ["text": "Hello"],
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        XCTAssertNil(model.getElementConfig(windowUUID: windowUUID, viewID: 1, key: "transport"))
    }

    func testSetElementConfigRingsObjectWillChange() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "properties": ["text": "Hello"],
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[1])

        var notified = false
        let cancellable = viewModel.objectWillChange.sink { _ in
            notified = true
        }
        model.setElementConfig(windowUUID: windowUUID, viewID: 1, key: "mode", value: "live")
        cancellable.cancel()
        XCTAssertTrue(notified, "setElementConfig must notify observers like setElementProperty does")
    }

    // MARK: - The canonical injection flow

    // The pattern hosts use for runtime/session-specific settings: load the static
    // document (models register synchronously), inject config, and only then build the
    // view - the first build must see the injected value, not the document's.
    func testInjectedConfigWinsBeforeFirstBuild() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "config": ["transport": ["command": ["placeholder"]]],
            "properties": ["text": "Hello"],
        ]
        let model = ActionUIModel.shared
        let element = try model.loadDescription(from: elementDict, windowUUID: windowUUID)

        model.setElementConfig(windowUUID: windowUUID, viewID: 1, key: "transport",
                               value: ["command": ["/usr/local/bin/agent", "acp"], "cwd": "/Users/me"])

        // First build happens after injection (ActionUIView.body reads the ViewModel).
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[1])
        _ = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID).body

        let transport = try XCTUnwrap(viewModel.config["transport"] as? [String: Any])
        XCTAssertEqual(transport["command"] as? [String], ["/usr/local/bin/agent", "acp"],
                       "the element's first build must see the injected transport, not the document placeholder")
    }
}
