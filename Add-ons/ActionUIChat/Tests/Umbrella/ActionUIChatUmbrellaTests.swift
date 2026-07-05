// Add-ons/ActionUIChat/Tests/Umbrella/ActionUIChatUmbrellaTests.swift
//
// The umbrella contract (P0-6): `import ActionUIChat` + `ActionUIChat.register()` must
// wire the element plus every bundled transport in one call, preserving the single-import
// experience after the module split. `@testable import ActionUIChatCore` reads the
// transport registry to prove the wiring.

import XCTest
import ActionUIChat
@testable import ActionUIChatCore

@MainActor
final class ActionUIChatUmbrellaTests: XCTestCase {

    func testRegisterWiresBundledTransports() {
        ActionUIChat.register()

        // The built-in `local` transport is always available.
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("local"))

        // The umbrella register() wires every bundled transport. OpenAI SSE is
        // cross-platform (URLSession); ACP is macOS-only (an agent runs as a subprocess),
        // so on other platforms it is a no-op and `acp` degrades to local.
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("openai-sse"),
                      "ActionUIChat.register() must wire the OpenAI SSE transport")
#if os(macOS)
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("acp"),
                      "ActionUIChat.register() must wire the ACP transport")
#endif
    }

    func testUmbrellaRegisterTransportForwardsToCore() {
        ActionUIChat.registerTransport("umbrella-test-custom") { config, logger in
            LocalChatTransport(config: config, logger: logger)
        }
        XCTAssertTrue(ChatTransportRegistry.shared.isRegistered("umbrella-test-custom"),
                      "ActionUIChat.registerTransport must forward to the core registry")
    }
}
