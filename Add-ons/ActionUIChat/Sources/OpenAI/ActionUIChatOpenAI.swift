// Add-ons/ActionUIChat/Sources/OpenAI/ActionUIChatOpenAI.swift
//
// Public entry point for the Chat add-on's OpenAI SSE transport module. The transport
// itself (OpenAIChatTransport: streams an OpenAI-compatible /v1/chat/completions endpoint
// - llama-server, mlx_lm.server, or any compatible server) lives in the ChatView package's
// ChatViewOpenAI product; this module is the register shim that preserves the add-on's
// established module split and C entry point. A host that wants plain chat links this
// module and calls ActionUIChatOpenAI.register() in addition to registering the element
// (via ActionUIChatCore.register() or the umbrella ActionUIChat.register(), which does both).
//
// Cross-platform: unlike ACP, this transport is not macOS-gated (URLSession works
// everywhere). The strong reference from register() to ChatViewOpenAI is what makes the
// linker extract the transport archive member - linking the module and registering the
// transport are the same fact by construction.

import Foundation
import ActionUIChatCore
import ChatViewOpenAI

public enum ActionUIChatOpenAI {

    /// Registers the `openai-sse` transport with the shared Chat transport registry. Call
    /// once at app launch, before building any Chat window. Idempotent (last registration
    /// for a name wins).
    @MainActor
    public static func register() {
        ChatViewOpenAI.register()
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
