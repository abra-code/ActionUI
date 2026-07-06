// Add-ons/ActionUIChat/Tests/Core/ChatTransportCommandGuardTests.swift
//
// Tests for the P0-3 transport-command security guard: a transport.command that came from the JSON
// document (not a host setElementConfig injection) is stripped so the element cannot spawn a
// subprocess a document requested; a host-injected command is honored. The pure guard function is
// tested here; Chat.buildView supplies the live origin (the origin bit comes from core's
// ViewModel.isConfigHostInjected, exercised at the app level).

import XCTest
@testable import ActionUIChatCore
import ActionUI

private final class GuardTestLogger: ActionUILogger {
    func log(_ message: String, _ level: LoggerLevel) {}
}

final class ChatTransportCommandGuardTests: XCTestCase {

    private func acpConfig() -> [String: Any] {
        ["protocol": "acp", "transport": ["command": ["opencode", "acp"], "cwd": "~"]]
    }

    func testDocumentOriginCommandIsStripped() {
        let gated = ChatConfig.applyingTransportCommandGuard(
            acpConfig(), transportHostInjected: false, logger: GuardTestLogger())
        XCTAssertNil((gated["transport"] as? [String: Any])?["command"], "a document-origin command is stripped")
        XCTAssertEqual((gated["transport"] as? [String: Any])?["cwd"] as? String, "~", "other transport keys are preserved")
    }

    func testHostInjectedCommandIsHonored() {
        let kept = ChatConfig.applyingTransportCommandGuard(
            acpConfig(), transportHostInjected: true, logger: GuardTestLogger())
        XCTAssertEqual((kept["transport"] as? [String: Any])?["command"] as? [String], ["opencode", "acp"],
                       "a host-injected (setElementConfig) command is honored")
    }

    func testTransportWithoutCommandIsUnaffected() {
        let config: [String: Any] = ["protocol": "local", "transport": ["echo": true]]
        let same = ChatConfig.applyingTransportCommandGuard(
            config, transportHostInjected: false, logger: GuardTestLogger())
        XCTAssertEqual((same["transport"] as? [String: Any])?["echo"] as? Bool, true, "a transport with no command passes through")
    }

    // Fed to ChatConfig, a gated config has no command, so the acp transport init throws and the
    // registry degrades to local (the element renders the degraded state).
    func testGatedAcpConfigLeavesNoCommandSoTheTransportDegrades() {
        let gated = ChatConfig.applyingTransportCommandGuard(
            acpConfig(), transportHostInjected: false, logger: GuardTestLogger())
        let chatConfig = ChatConfig(properties: [:], config: gated, logger: GuardTestLogger())
        XCTAssertEqual(chatConfig.protocolName, "acp", "the protocol name is unchanged; the registry degrades on the missing command")
        XCTAssertNil(chatConfig.transport["command"], "the gated transport carries no command, so acp init throws -> degrade to local")
    }
}
