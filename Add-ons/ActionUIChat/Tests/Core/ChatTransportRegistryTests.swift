// Add-ons/ActionUIChat/Tests/Core/ChatTransportRegistryTests.swift
//
// Unit tests for the transport registry (P0-6): a registered factory builds its own
// transport; the reserved `local` name cannot be overridden; the latest registration
// for a name wins; an unregistered name and a throwing factory both degrade to the
// built-in `local` transport. The registry is a main-actor singleton with no unregister
// API, so each test uses a protocol name unique to it to avoid cross-test pollution.

import XCTest
@testable import ActionUIChatCore
import ActionUI

private final class RegistryTestLogger: ActionUILogger {
    func log(_ message: String, _ level: LoggerLevel) {}
}

/// A stand-in transport a test factory returns, tagged so a test can prove which factory ran.
private final class FakeTransport: ChatTransport, @unchecked Sendable {
    let events: AsyncStream<ChatEvent>
    private let continuation: AsyncStream<ChatEvent>.Continuation
    let marker: String

    init(marker: String) {
        self.marker = marker
        var captured: AsyncStream<ChatEvent>.Continuation!
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func start() async {}
    func send(_ command: ChatCommand) async {}
    func stop() async {
        continuation.finish()
    }
}

@MainActor
final class ChatTransportRegistryTests: XCTestCase {

    private func config(protocolName: String) -> ChatConfig {
        ChatConfig(properties: [:], config: ["protocol": protocolName], logger: RegistryTestLogger())
    }

    private func make(_ protocolName: String) -> any ChatTransport {
        ChatTransportRegistry.shared.make(config(protocolName: protocolName), logger: RegistryTestLogger())
    }

    func testRegisteredFactoryBuildsItsTransport() {
        ChatTransportRegistry.shared.register("registry-test-basic") { config, _ in
            FakeTransport(marker: "basic:\(config.protocolName)")
        }
        let transport = make("registry-test-basic")
        XCTAssertEqual((transport as? FakeTransport)?.marker, "basic:registry-test-basic",
                       "the registered factory should build the transport, and see the resolved protocol name")
    }

    func testUnregisteredProtocolDegradesToLocal() {
        let transport = make("registry-test-unregistered-name")
        XCTAssertTrue(transport is LocalChatTransport, "an unregistered protocol must degrade to the built-in local transport")
    }

    func testLocalIsBuiltInWithoutRegistration() {
        XCTAssertTrue(make("local") is LocalChatTransport)
    }

    func testLocalNameIsReservedAndNotOverridable() {
        ChatTransportRegistry.shared.register("local") { _, _ in FakeTransport(marker: "hijack") }
        XCTAssertTrue(make("local") is LocalChatTransport, "registering 'local' must be ignored; the built-in always wins")
    }

    func testLastRegistrationWins() {
        ChatTransportRegistry.shared.register("registry-test-override") { _, _ in FakeTransport(marker: "first") }
        ChatTransportRegistry.shared.register("registry-test-override") { _, _ in FakeTransport(marker: "second") }
        XCTAssertEqual((make("registry-test-override") as? FakeTransport)?.marker, "second")
    }

    func testEmptyNameIsIgnored() {
        ChatTransportRegistry.shared.register("") { _, _ in FakeTransport(marker: "empty") }
        XCTAssertFalse(ChatTransportRegistry.shared.isRegistered(""))
    }

    func testThrowingFactoryDegradesToLocal() {
        struct FactoryError: Error {}
        ChatTransportRegistry.shared.register("registry-test-throws") { _, _ in throw FactoryError() }
        XCTAssertTrue(make("registry-test-throws") is LocalChatTransport,
                      "a factory that throws must degrade to local, not propagate the error")
    }

    func testIsRegistered() {
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("local"), "the built-in local is always registered")
        XCTAssertFalse(ChatTransportRegistry.shared.isRegistered("registry-test-never-registered"))
        ChatTransportRegistry.shared.register("registry-test-present") { _, _ in FakeTransport(marker: "present") }
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("registry-test-present"))
    }
}
