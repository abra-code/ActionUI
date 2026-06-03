package com.abracode.actionui.Common

import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * Owns the runtime state for a single window: its root [element] and the pool of
 * [ViewModel]s keyed by element id. The Android counterpart of Swift's
 * `WindowModel` (`ActionUI/Common/WindowModel.swift`), trimmed to what the
 * Android renderer can actually drive today.
 *
 * `ActionUI.Render` builds one of these per document (via
 * [ActionUIModel.loadDescription]) and exposes it to the element tree through
 * [LocalWindowModel], so a value-bearing builder can find *its* [ViewModel] by
 * `viewModels[element.id]`. Because the [ViewModel] fields are Compose snapshot
 * state, host-side mutations through the `ActionUIModel` value/state API
 * recompose the affected control with no explicit change notification.
 *
 * ## Deferred vs. the Swift WindowModel
 *
 * The Swift model also performs JSON/plist decoding, sub-view and modal loading,
 * and runtime structural mutation (`insertElement` / `insertRow` /
 * `removeElement`) by walking many named subview containers. None of that is
 * ported: Android decodes JSON in `ActionUI.Render`, has no modal/template
 * layer, and its [ActionUIElement] models only a flat `children` list (no
 * `rows` / `sidebar` / `detail` / ... containers). So [populateViewModels] is a
 * plain recursion over `children`. Those features land with the elements that
 * need them.
 */
class WindowModel(
    val windowUUID: String,
    private val logger: ActionUILogger,
) {
    /** The window's root element, set by [loadDescription]. */
    var element: ActionUIElement? = null
        private set

    /** Per-element runtime state, keyed by element id. */
    val viewModels: MutableMap<Int, ViewModel> = mutableMapOf()

    /**
     * Adopts [root] as the window's element and (re)builds the [ViewModel] pool
     * from it, seeding each value-bearing element's initial value. Mirrors the
     * Swift `loadDescription`, minus the decoding (the caller decodes).
     */
    fun loadDescription(root: ActionUIElement): ActionUIElement {
        element = root
        viewModels.clear()
        populateViewModels(root, into = viewModels)
        logger.log(
            "Loaded description for windowUUID: $windowUUID, element id: ${root.id}, " +
                "${viewModels.size} view model(s)",
            LoggerLevel.verbose
        )
        return root
    }

    /**
     * Recursively creates a [ViewModel] for [element] and every descendant in
     * its `children`, seeding the initial value for value-bearing elements from
     * the registered builder. Elements with no explicit `id` share id 0 (last
     * one wins); the value/state API is only meaningful for elements that carry
     * a positive, unique id, as on the Apple side.
     */
    private fun populateViewModels(element: ActionUIElement, into: MutableMap<Int, ViewModel>) {
        val viewModel = ViewModel()
        viewModel.elementType = element.type
        val builder = ActionUIRegistry.lookup(element.type)
        if (builder != null && builder.valueType != ActionUIValueType.NONE) {
            viewModel.value = builder.initialValue(element)
        }
        into[element.id] = viewModel

        element.children?.forEach { populateViewModels(it, into) }
    }
}

/**
 * CompositionLocal carrying the active [WindowModel] through the rendered tree.
 * `ActionUI.Render` provides it; value-bearing builders read
 * `LocalWindowModel.current?.viewModels?.get(element.id)` to bind to their
 * runtime [ViewModel]. The same pattern as [LocalActionUILogger] /
 * `LocalStackAxis`.
 *
 * Defaults to `null` so a control rendered without a hosting window (or in a
 * context that never set one up) degrades gracefully to local composition state
 * instead of crashing. `staticCompositionLocalOf` because the value is set once
 * at the render root and does not change within the tree.
 */
val LocalWindowModel: ProvidableCompositionLocal<WindowModel?> =
    staticCompositionLocalOf { null }
