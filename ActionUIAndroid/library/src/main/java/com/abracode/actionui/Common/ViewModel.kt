package com.abracode.actionui.Common

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

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
 * ## Properties at runtime
 *
 * Swift's `validatedProperties` is one mutable dictionary holding the authored
 * (validated) properties that `setElementProperty` then mutates in place. The
 * Android split keeps the authored JSON immutable and observes only the runtime
 * writes: [authoredProperties] is the element's decoded `properties` object
 * (seeded by `WindowModel.populateViewModels`), and [propertyOverrides] is a
 * [SnapshotStateMap] of host-set values layered over it. The shared build entry
 * point (`Helpers/ViewModifierHelper.kt`) merges the two into the element each
 * recomposition, so a `setElementProperty` write reaches every property consumer
 * - the modifier chain and the element builder alike - exactly as on Apple,
 * where views read `validatedProperties`. Android has no central validation
 * stage (an open decision in the porting notes); overridden values are
 * validated warn-and-skip at read time like authored ones.
 *
 * [mutationToken] increments on every `setElementProperty` / `setElementState`
 * / `setElementValue` call, mirroring the Swift member: it is the default
 * watched value of the `animation` modifier ("animate any mutation",
 * `Helpers/AnimationHelper.kt`). The Apple-side `PendingUpdateTracker`
 * cursor-jump guard it also feeds has no Android analog (no async model layer,
 * see above).
 *
 * ## Deferred vs. the Swift ViewModel
 *
 * The following Swift members are intentionally **not** ported here, because the
 * Android features that drive them are themselves not ported:
 *
 *   * `templateContext` - data-driven template rendering (List rows, ZStack
 *     templates) is not ported.
 *   * `dynamicSubviews` - runtime structural mutation (insertElement /
 *     removeElement / insertRow) is not ported.
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
     * The element's authored `properties` JSON, as decoded (and platform-
     * filtered) from the document. Immutable; the read-side base layer of
     * [ActionUIModel.getElementProperty] and of the effective-properties merge.
     */
    var authoredProperties: JsonObject? = null
        internal set

    /**
     * Host-set property values ([ActionUIModel.setElementProperty]) layered over
     * [authoredProperties], stored as [JsonElement] so the merge back into the
     * element's `properties` object is direct. Backed by a [SnapshotStateMap]:
     * the shared build entry point reads it during composition, so a property
     * write recomposes the element with the new value.
     */
    val propertyOverrides: SnapshotStateMap<String, JsonElement> = mutableStateMapOf()

    /**
     * Increments on every `setElementProperty` / `setElementState` /
     * `setElementValue` call (the Swift `mutationToken` contract). Snapshot
     * state: the `animation` modifier watches it (its default "animate any
     * mutation" trigger) by reading it during composition.
     */
    var mutationToken: Int by mutableStateOf(0)
        internal set
}
