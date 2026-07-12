// Add-ons/ActionUIChat/Sources/Core/ActionUIChatCore.swift
//
// Public entry point for the Chat add-on's CORE module: the `Chat` element glue over the
// standalone ChatView package. The component (transcript / store / views, the built-in
// `local` and `local-p2p` transports, and the transport registry) lives in ChatView and is
// re-exported here, so a host that imports ActionUIChatCore (or the umbrella) still sees
// the frozen transport contract (ChatTransport, ChatEvent, ChatCommand, ...) unchanged.
// A host that links only ActionUIChatCore gets the element and the built-ins; any other
// protocol degrades to `local` with a clear log. To make another protocol available, link
// its module and call its register() (e.g. ActionUIChatACP.register()), or a host can
// register its own transport with `registerTransport`.
//
// Most hosts link the umbrella `ActionUIChat` product and call `ActionUIChat.register()`
// instead, which registers the element and every bundled transport in one call.
//
// This library compiles against ActionUI's public API but does not link the ActionUI
// static library; the host app links ActionUI (and this add-on) and calls register()
// once at launch, before any window that references the "Chat" element is built. Apple
// has no guaranteed pre-main hook for a statically linked Swift type, so registration
// is this one explicit call.

import Foundation
import ActionUI
@_exported import ChatView

public enum ActionUIChatCore {

    /// Registers the `Chat` element type with the shared ActionUI registry and routes the
    /// component registry's registration-time diagnostics into the host's ActionUI logger.
    /// Call once at app launch, before building any window that uses "Chat". Idempotent:
    /// a second call simply re-binds the same token.
    @MainActor
    public static func register() {
        ChatTransportRegistry.shared.logger = ChatLoggerAdapter(base: ActionUIModel.shared.logger)
        ActionUIRegistry.shared.register(Chat.self)   // JSON token: "Chat"
    }

    /// Registers a transport factory under a protocol name (the element's
    /// `config.protocol`). Main-actor-confined, like `register()`; call at launch,
    /// before any Chat window is built. Last registration for a name wins; the reserved
    /// name `local` (the built-in) cannot be overridden. A host adds a new protocol -
    /// with no change to the component - by calling this with its own factory.
    @MainActor
    public static func registerTransport(_ name: String, factory: @escaping ChatTransportFactory) {
        ChatTransportRegistry.shared.register(name, factory: factory)
    }
}

/// Plain C entry point so any host adapter - C, C++, Objective-C, or Objective-C++ -
/// can register the core element + built-in transports without the Swift or Objective-C
/// runtime. Mirrors the umbrella's `ActionUIChat_register`. `@_cdecl` symbols are not
/// emitted into the generated `-Swift.h`, so the caller forward-declares it:
///
///     extern void ActionUIChatCore_register(void);    // C / Objective-C
///     extern "C" void ActionUIChatCore_register(void); // C++ / Objective-C++
///
/// Must be called on the main thread, at launch, before any window that uses the `Chat`
/// element is built. `MainActor.assumeIsolated` enforces the main-thread contract (it
/// traps otherwise) and lets this nonisolated C function reach the main-actor-isolated registry.
@_cdecl("ActionUIChatCore_register")
public func ActionUIChatCore_register() {
    MainActor.assumeIsolated {
        ActionUIChatCore.register()
    }
}
