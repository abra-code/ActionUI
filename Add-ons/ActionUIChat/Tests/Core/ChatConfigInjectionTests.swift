// Add-ons/ActionUIChat/Tests/Core/ChatConfigInjectionTests.swift
//
// Tests for the host-injected operational-config seam (states["config"]). The Chat
// element takes its protocol + transport NOT from the document but from a runtime
// injection into states["config"] (the same @Published states channel as the P0-2
// states["content"] restore). The store DEFERS building the transport until the config
// first resolves to a VIABLE one, then FREEZES it - a later states["config"] change is
// ignored (a new element is needed to switch transport). Until configured the element is
// inert (isConfigured == false, no transport); readOnly never builds a transport.

import XCTest
import Combine
@testable import ActionUIChatCore
import ActionUI

private final class InjectionTestLogger: ActionUILogger {
    func log(_ message: String, _ level: LoggerLevel) {}
}

/// A fake ChatContentSource that drives states["config"] (and states["content"]) the way the
/// engine's ViewModel does: assigning `config` delivers it to observers, and a new observer receives
/// the current value immediately (matching the @Published semantics the store relies on).
@MainActor
private final class FakeConfigSource: ChatContentSource {
    var content: Any? {
        didSet { contentObservers.values.forEach { $0(content) } }
    }
    var config: Any? {
        didSet { configObservers.values.forEach { $0(config) } }
    }
    private var contentObservers: [Int: (Any?) -> Void] = [:]
    private var configObservers: [Int: (Any?) -> Void] = [:]
    private var nextID = 0

    init(config: Any? = nil) {
        self.config = config
    }

    func observeChatContent(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        nextID += 1
        let id = nextID
        contentObservers[id] = handler
        handler(content)
        return AnyCancellable { MainActor.assumeIsolated { self.contentObservers[id] = nil } }
    }

    func observeChatConfig(_ handler: @escaping (Any?) -> Void) -> AnyCancellable {
        nextID += 1
        let id = nextID
        configObservers[id] = handler
        handler(config)
        return AnyCancellable { MainActor.assumeIsolated { self.configObservers[id] = nil } }
    }
}

/// A mutable build counter shared with a test factory so a test can prove how many times the
/// transport was built (the freeze: a frozen element must not rebuild on a later config change).
private final class BuildCounter: @unchecked Sendable {
    var count = 0
}

/// A no-op transport a test factory returns; its event stream never emits (the store just drains it).
private final class FakeInjectTransport: ChatTransport, @unchecked Sendable {
    let events: AsyncStream<ChatEvent>
    private let continuation: AsyncStream<ChatEvent>.Continuation
    init() {
        var captured: AsyncStream<ChatEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }
    func start() async {}
    func send(_ command: ChatCommand) async {}
    func stop() async { continuation.finish() }
}

@MainActor
final class ChatConfigInjectionTests: XCTestCase {

    private func makeStore(properties: [String: Any] = [:], source: FakeConfigSource) -> ChatStore {
        let logger = InjectionTestLogger()
        return ChatStore(config: ChatConfig(properties: properties, logger: logger),
                         windowUUID: "config-window", elementID: 1, logger: logger, contentSource: source)
    }

    // NOTE: ChatStore holds `contentSource` WEAKLY (the engine's ViewModel owns the store's lifetime,
    // not vice versa - a strong ref would retain-cycle). So every test must keep a STRONG local `source`
    // alive across start(), exactly as the engine keeps the ViewModel alive; passing the fake inline
    // would let it deallocate before the subscription fires.

    func testInertWithNoConfigInjected() {
        let source = FakeConfigSource()   // no states["config"]
        let store = makeStore(source: source)
        store.start()
        XCTAssertFalse(store.isConfigured, "with no states[\"config\"] injected, the element stays inert (no transport)")
    }

    func testLocalConfigBuildsTransport() {
        let source = FakeConfigSource(config: ["protocol": "local"])
        let store = makeStore(source: source)
        store.start()
        XCTAssertTrue(store.isConfigured, "an injected local config builds the built-in transport")
        store.teardown()
    }

    func testMissingProtocolDefaultsToLocal() {
        let source = FakeConfigSource(config: ["transport": ["echo": true]])
        let store = makeStore(source: source)
        store.start()
        XCTAssertTrue(store.isConfigured, "a config object without a protocol defaults to local and is viable")
        store.teardown()
    }

    func testReadOnlyNeverBuildsTransportEvenWhenConfigInjected() {
        let source = FakeConfigSource(config: ["protocol": "local"])
        let store = makeStore(properties: ["readOnly": true], source: source)
        store.start()
        XCTAssertFalse(store.isConfigured, "readOnly is a viewer mode: no transport even when a config is injected")
    }

    func testNotYetViableConfigDefersThenBuildsOnCompleterConfig() {
        struct MissingKey: Error {}
        let name = "inject-test-needs-key-\(UUID().uuidString)"
        ChatTransportRegistry.shared.register(name) { config, _ in
            guard config.settings["key"] != nil else { throw MissingKey() }
            return FakeInjectTransport()
        }
        let source = FakeConfigSource(config: ["protocol": name])   // registered but incomplete -> not viable
        let store = makeStore(source: source)
        store.start()
        XCTAssertFalse(store.isConfigured, "a registered-but-incomplete config does not build or freeze; the element stays inert")

        source.config = ["protocol": name, "transport": ["key": "v"]]   // the host completes the config
        XCTAssertTrue(store.isConfigured, "when a completer config arrives, the deferred transport builds")
        store.teardown()
    }

    func testFrozenAfterFirstViableConfig() {
        let counter = BuildCounter()
        let name = "inject-test-freeze-\(UUID().uuidString)"
        ChatTransportRegistry.shared.register(name) { _, _ in
            counter.count += 1
            return FakeInjectTransport()
        }
        let source = FakeConfigSource(config: ["protocol": name])
        let store = makeStore(source: source)
        store.start()
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(counter.count, 1, "the first viable config builds the transport once")

        // A later states["config"] change must be ignored (frozen): the factory must not run again.
        source.config = ["protocol": name, "transport": ["changed": true]]
        XCTAssertEqual(counter.count, 1, "after the first viable build the element is frozen; a later states[\"config\"] change is ignored")
        store.teardown()
    }
}
