// Add-ons/ActionUIChat/Sources/OpenAI/ActionUIChatOpenAI.swift
//
// Public entry point for the OpenAI SSE transport module. Links against ActionUIChatCore
// and registers the `openai-sse` transport factory so a document with
// `"protocol": "openai-sse"` resolves to a streaming OpenAI-compatible chat-completions
// backend (llama-server, mlx_lm.server, or any /v1/chat/completions endpoint). A host that
// wants plain chat links this module and calls ActionUIChatOpenAI.register() in addition to
// registering the element (via ActionUIChatCore.register() or the umbrella
// ActionUIChat.register(), which does both).
//
// Cross-platform: unlike ACP, this transport is not macOS-gated (URLSession works
// everywhere). The strong reference from register() to ChatTransportRegistry is what makes
// the linker extract this archive member - linking the module and registering the transport
// are the same fact by construction.

import Foundation
import ActionUIChatCore

public enum ActionUIChatOpenAI {

    /// Registers the `openai-sse` transport with the shared Chat transport registry. Call
    /// once at app launch, before building any Chat window. Idempotent (last registration
    /// for a name wins).
    @MainActor
    public static func register() {
        ActionUIChatCore.registerTransport("openai-sse") { config, logger in
            try OpenAIChatTransport(config: config, logger: logger)
        }
    }
}

/// Plain C entry point mirroring ActionUIChat_register / ActionUIChatCore_register, so a
/// non-Swift host adapter can register the OpenAI transport. The caller forward-declares it:
///
///     extern void ActionUIChatOpenAI_register(void);    // C / Objective-C
///     extern "C" void ActionUIChatOpenAI_register(void); // C++ / Objective-C++
///
/// Must be called on the main thread at launch.
@_cdecl("ActionUIChatOpenAI_register")
public func ActionUIChatOpenAI_register() {
    MainActor.assumeIsolated {
        ActionUIChatOpenAI.register()
    }
}
