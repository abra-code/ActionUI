// Add-ons/ActionUIChat/Sources/ACP/ActionUIChatACP.swift
//
// Public entry point for the ACP transport module. Links against ActionUIChatCore and
// registers the `acp` transport factory so a document with `"protocol": "acp"` resolves
// to an ACP agent subprocess. A host that wants ACP links this module and calls
// ActionUIChatACP.register() in addition to registering the element (via
// ActionUIChatCore.register() or the umbrella ActionUIChat.register(), which does both).
//
// The strong reference from this register() to ChatTransportRegistry is what makes the
// linker extract this archive member: linking the module and registering the transport
// are the same fact by construction.

import Foundation
import ActionUIChatCore

public enum ActionUIChatACP {

    /// Registers the `acp` transport with the shared Chat transport registry. Call once
    /// at app launch, before building any Chat window. Idempotent (last registration for
    /// a name wins). macOS only - an ACP agent runs as a subprocess, which iOS cannot
    /// spawn; on other platforms this is a no-op and `acp` degrades to `local` like any
    /// unregistered protocol.
    @MainActor
    public static func register() {
#if os(macOS)
        ActionUIChatCore.registerTransport("acp") { config, logger in
            try ACPChatTransport(config: config, logger: logger)
        }
#endif
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
