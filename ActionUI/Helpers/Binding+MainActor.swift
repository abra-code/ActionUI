// Helpers/Binding+MainActor.swift

import SwiftUI

/// Creates a Binding whose get/set are main-actor isolated.
///
/// SwiftUI always drives a Binding's get/set on the main actor (they read and write view state
/// during layout and event handling), but `Binding.init(get:set:)` types those closures as
/// `@Sendable`, which strips main-actor isolation. That makes a hand-rolled binding warn whenever
/// its get/set touch `@MainActor` state (the ViewModel's `value` / `states`) or capture the
/// non-Sendable `[String: Any]` properties payload.
///
/// This factory takes `@MainActor` get/set instead, so call sites can do both freely, and
/// re-asserts the isolation at runtime via `MainActor.assumeIsolated` - which always holds,
/// because SwiftUI only ever invokes these on the main actor.
///
/// Implemented as a free function rather than a `Binding` static member: `Binding` is
/// `@dynamicMemberLookup`, which makes `Binding<T>.someName` parse as a dynamic-member key path
/// and shadows a static method of the same name in the editor/index.
///
/// The `nonisolated(unsafe)` result/value boxes are needed because `MainActor.assumeIsolated`
/// constrains its return to `Sendable`, while a binding's `Value` need not be Sendable. The boxes
/// never cross threads (the write and the read both happen synchronously on the main actor inside
/// the same call), so this is safe; it mirrors the `runOnMainActorSync` pattern.
@MainActor
func mainActorBinding<Value>(get: @escaping @MainActor () -> Value,
                             set: @escaping @MainActor (Value) -> Void) -> Binding<Value> {
    Binding(
        get: {
            nonisolated(unsafe) var result: Value!
            MainActor.assumeIsolated { result = get() }
            return result
        },
        set: { newValue in
            nonisolated(unsafe) let captured = newValue
            MainActor.assumeIsolated { set(captured) }
        }
    )
}
