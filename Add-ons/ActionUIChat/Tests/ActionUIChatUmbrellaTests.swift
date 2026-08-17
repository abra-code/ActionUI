// Add-ons/ActionUIChat/Tests/ActionUIChatUmbrellaTests.swift
//
// The umbrella contract (P0-6): `import ActionUIChat` + `ActionUIChat.register()` must
// wire the element plus every bundled transport in one call, preserving the single-import
// experience after the module split (and after the component's extraction into the
// ChatView package). The component registry's public isRegistered proves the wiring.

import XCTest
import ActionUIChat

/// A minimal transport for the custom-registration test (the component's built-in
/// LocalChatTransport is internal to the ChatView module).
private final class FakeUmbrellaTransport: ChatTransport, @unchecked Sendable {
    let events: AsyncStream<ChatEvent> = AsyncStream { continuation in
        continuation.finish()
    }
    func start() async {}
    func send(_ command: ChatCommand) async {}
    func stop() async {}
}

@MainActor
final class ActionUIChatUmbrellaTests: XCTestCase {

    func testRegisterWiresBundledTransports() {
        ActionUIChat.register()

        // The built-in transports are always available: `local` is reserved, `local-p2p`
        // is seeded by the component registry.
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("local"))
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("local-p2p"))

        // The umbrella register() wires every bundled transport. Three of the four are
        // cross-platform: OpenAI SSE and acp-remote own no subprocess (URLSession and a
        // WebSocket to a bridge respectively), so they register everywhere. Only `acp` is
        // macOS-only - its agent runs as a subprocess - and elsewhere it degrades to local.
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("openai-sse"),
                      "ActionUIChat.register() must wire the OpenAI SSE transport")
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("acp-remote"),
                      "ActionUIChat.register() must wire the remote ACP transport on every platform")
#if os(macOS)
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("acp"),
                      "ActionUIChat.register() must wire the ACP transport")
#endif
    }

    func testUmbrellaRegisterTransportForwardsToCore() {
        ActionUIChat.registerTransport("umbrella-test-custom") { _, _ in
            FakeUmbrellaTransport()
        }
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("umbrella-test-custom"),
                      "ActionUIChat.registerTransport must forward to the component registry")
    }
}
