package com.abracode.actionui.Common

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap

/**
 * Per-view runtime state holder. The Android counterpart of Swift's
 * `ViewModel` (`ActionUI/Common/ViewModel.swift`), one instance per element id,
 * owned by the enclosing [WindowModel] and looked up by element builders via
 * [LocalWindowModel].
 *
 * ## Compose state interop (the load-bearing decision)
 *
 * Swift's `ViewModel` is an `ObservableObject` whose `@Published var value` /
 * `var states` drive SwiftUI refresh through `objectWillChange.send()`. The
 * Android analog uses **Compose snapshot state**: [value] is backed by
 * `mutableStateOf` and [states] by `mutableStateMapOf`. A `@Composable` builder
 * that reads `viewModel.value` is automatically subscribed, so when the host
 * calls `ActionUIModel.setElementValue(...)` and that writes [value], the field
 * recomposes - exactly the role `@Published` + `objectWillChange` plays on
 * Apple, with no `objectWillChange.send()` call needed.
 *
 * Snapshot state was chosen over a `StateFlow`-backed holder because the value
 * is read *directly inside composition* (a `StateFlow` would force a
 * `collectAsState` indirection) and because all mutation happens on the main
 * thread from Compose callbacks or host handlers - the same single-threaded,
 * no-`@MainActor`-analog stance [ActionUIModel] already takes. There is no async
 * model layer, which is also why TextEditor needs no cursor-jump hardening (see
 * `Private/Android_Porting_Notes.md` section 14).
 *
 * ## Deferred vs. the Swift ViewModel
 *
 * The following Swift members are intentionally **not** ported here, because the
 * Android features that drive them are themselves not ported:
 *
 *   * `mutationToken` - exists on Apple only to feed the `PendingUpdateTracker`
 *     cursor-jump guard, which is unnecessary without an async model (above).
 *   * `templateContext` - data-driven template rendering (List rows, ZStack
 *     templates) is not ported.
 *   * `dynamicSubviews` - runtime structural mutation (insertElement /
 *     removeElement / insertRow) is not ported.
 *   * `validatedProperties` is present but holds the raw properties: Android has
 *     no central validation stage yet (an open decision in the porting notes).
 */
class ViewModel {
    /**
     * The element's current value (e.g. a text field's string). Backed by
     * Compose snapshot state so reads inside composition subscribe and host-side
     * writes through [ActionUIModel.setElementValue] trigger recomposition.
     */
    var value: Any? by mutableStateOf(null)

    /**
     * View-specific state keyed by name (e.g. a future ProgressView's
     * `"progress"`). Backed by a [SnapshotStateMap] for per-key observability,
     * mirroring the Swift `@Published var states`.
     */
    val states: SnapshotStateMap<String, Any> = mutableStateMapOf()

    /** The element's type name (e.g. "TextField"). Used by the value-string API. */
    var elementType: String = ""

    /**
     * The element's validated properties. With no central validation stage on
     * Android yet, this is populated with the element's raw properties when the
     * window is loaded; the slot exists so the property API can be added without
     * a later signature change.
     */
    var validatedProperties: Map<String, Any> = emptyMap()
}
