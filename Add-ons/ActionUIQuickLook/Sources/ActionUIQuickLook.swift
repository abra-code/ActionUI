// Add-ons/ActionUIQuickLook/Sources/ActionUIQuickLook.swift
//
// Public entry point for the ActionUIQuickLook add-on.
//
// This library is a separately-linkable ActionUI add-on. It compiles against ActionUI's
// public API but does not link the ActionUI static library; the host app links ActionUI
// (and this add-on) and calls ActionUIQuickLook.register() once at launch, before any
// window that references the "QuickLook" element is built.
//
// Apple has no guaranteed pre-main hook for a statically linked Swift type (unlike the
// ActionUIAndroid map providers, which self-register via a manifest ContentProvider), so
// registration is this one explicit call.

import Foundation
import ActionUI

public enum ActionUIQuickLook {

    /// Registers the `QuickLook` element type with the shared ActionUI registry.
    /// Call once at app launch, before building any window that uses "QuickLook".
    /// Idempotent: a second call simply re-binds the same token.
    @MainActor
    public static func register() {
        ActionUIRegistry.shared.register(QuickLook.self)   // JSON token: "QuickLook"
    }
}

/// Plain C entry point so any host adapter - C, C++, Objective-C, or Objective-C++ (e.g. OMC's
/// Abracode.framework) - can register the element without the Swift or Objective-C runtime. This is
/// more universal than an `@objc` class method: a free C symbol is callable from every adapter.
///
/// `@_cdecl` symbols are not emitted into the generated `-Swift.h`, so the caller forward-declares it:
///
///     extern void ActionUIQuickLook_register(void);   // C / Objective-C
///     extern "C" void ActionUIQuickLook_register(void); // C++ / Objective-C++
///
/// Must be called on the main thread, at launch, before any window that uses the `QuickLook` element
/// is built. `MainActor.assumeIsolated` enforces the main-thread contract (it traps otherwise) and
/// lets this nonisolated C function reach the main-actor-isolated registry.
@_cdecl("ActionUIQuickLook_register")
public func ActionUIQuickLook_register() {
    MainActor.assumeIsolated {
        ActionUIQuickLook.register()
    }
}
