// Add-ons/ActionUIChat/Sources/Umbrella/ActionUIChat.swift
//
// Public entry point for the ActionUIChat UMBRELLA: the single-import, batteries-included
// product. It depends on ActionUIChatCore and every bundled transport module (ActionUIChatACP,
// ActionUIChatOpenAI), and its register() wires them all in one call.
// This preserves today's experience for existing hosts, DemoApps, and the test suite:
// link the `ActionUIChat` product, `import ActionUIChat`, call `ActionUIChat.register()`.
//
// A host that wants a smaller footprint links `ActionUIChatCore` (element + `local`
// transport) and adds only the transport modules it needs, calling each module's
// register(). The strong reference from this umbrella register() to each module's
// register() is exactly what makes the linker pull that transport's archive in - so a
// host that links the umbrella gets every transport, and one that links Core picks a la carte.
//
// `@_exported import ActionUIChatCore` re-exports the element + the frozen transport API
// (ChatTransport, ChatEvent, ChatCommand, ChatTransportConfig, ...) so `import ActionUIChat`
// alone gives a host everything it needs to register a custom transport too.

import Foundation
@_exported import ActionUIChatCore
import ActionUIChatACP
import ActionUIChatOpenAI

public enum ActionUIChat {

    /// Registers the `Chat` element and every bundled transport (the built-in `local`,
    /// plus ACP and OpenAI SSE) with the shared registries. Call once at app launch,
    /// before building any window that uses "Chat". Idempotent.
    @MainActor
    public static func register() {
        ActionUIChatCore.register()
        ActionUIChatACP.register()
        ActionUIChatOpenAI.register()
    }

    /// Registers a host-provided transport factory under a protocol name. A thin
    /// forward to ActionUIChatCore.registerTransport, so a host that imports only the
    /// umbrella can add its own protocol without importing Core directly. Last
    /// registration for a name wins; `local` is reserved.
    @MainActor
    public static func registerTransport(_ name: String, factory: @escaping ChatTransportFactory) {
        ActionUIChatCore.registerTransport(name, factory: factory)
    }
}

/// Plain C entry point so any host adapter - C, C++, Objective-C, or Objective-C++ -
/// can register the element + every bundled transport without the Swift or Objective-C
/// runtime. This is more universal than an `@objc` class method: a free C symbol is
/// callable from every adapter. Unchanged symbol name, so existing C hosts keep working.
///
/// `@_cdecl` symbols are not emitted into the generated `-Swift.h`, so the caller forward-declares it:
///
///     extern void ActionUIChat_register(void);    // C / Objective-C
///     extern "C" void ActionUIChat_register(void); // C++ / Objective-C++
///
/// Must be called on the main thread, at launch, before any window that uses the `Chat` element is
/// built. `MainActor.assumeIsolated` enforces the main-thread contract (it traps otherwise) and lets
/// this nonisolated C function reach the main-actor-isolated registry.
@_cdecl("ActionUIChat_register")
public func ActionUIChat_register() {
    MainActor.assumeIsolated {
        ActionUIChat.register()
    }
}
