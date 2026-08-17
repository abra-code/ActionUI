// Add-ons/ActionUIChat/Sources/ACP/ActionUIChatACP.swift
//
// Public entry point for the Chat add-on's ACP transport module. The transports themselves
// live in the ChatView package's ChatViewACP product: ACPChatTransport (an Agent Client
// Protocol agent launched as a subprocess, newline-delimited JSON-RPC over stdio, macOS
// only) and ACPRemoteTransport (the same protocol carried to an agent on another machine
// over a WebSocket to a chatview-acp-bridge, on every platform). This module is the
// register shim that preserves the add-on's established module split and C entry point.
// A host that wants ACP links this module and calls
// ActionUIChatACP.register() in addition to registering the element (via
// ActionUIChatCore.register() or the umbrella ActionUIChat.register(), which does both).
//
// The strong reference from this register() to ChatViewACP is what makes the linker
// extract the transport archive member: linking the module and registering the transports
// are the same fact by construction.

import Foundation
import ActionUIChatCore
import ChatViewACP

public enum ActionUIChatACP {

    /// Registers the component's two ACP transports with the shared Chat transport registry. Call
    /// once at app launch, before building any Chat window. Idempotent (last registration for a
    /// name wins).
    ///
    /// - `acp` is macOS only - the agent runs as a subprocess, which iOS cannot spawn. On other
    ///   platforms it is not registered and degrades to `local` like any unregistered protocol.
    /// - `acp-remote` is registered on EVERY platform: it drives an ACP agent on another machine
    ///   over a WebSocket to a chatview-acp-bridge and owns no subprocess. It is also the only
    ///   transport that emits resume checkpoints, so a host wiring `resumeCheckpointActionID`
    ///   needs this module whatever platform it targets.
    @MainActor
    public static func register() {
        ChatViewACP.register()
    }
}

/// Plain C entry point mirroring ActionUIChat_register / ActionUIChatCore_register, so a
/// non-Swift host adapter can register the ACP transport. The caller forward-declares it:
///
///     extern void ActionUIChatACP_register(void);    // C / Objective-C
///     extern "C" void ActionUIChatACP_register(void); // C++ / Objective-C++
///
/// Must be called on the main thread at launch.
@_cdecl("ActionUIChatACP_register")
public func ActionUIChatACP_register() {
    MainActor.assumeIsolated {
        ActionUIChatACP.register()
    }
}
