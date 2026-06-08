package com.abracode.actionui.Common

import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
 * ported: Android decodes JSON in `ActionUI.Render` and has no modal/template
 * layer. [populateViewModels] recurses over [ActionUIElement.subElements], which
 * flattens every named container the model supports today (`children` and the
 * single-child `content`); the remaining containers (`rows` / `sidebar` /
 * `detail` / ...) land with the elements that need them.
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
     * The active window-level dialog (alert / confirmationDialog), or `null` when
     * none is presented. Backed by Compose snapshot state so
     * [ActionUIModel.presentAlert] / [ActionUIModel.presentConfirmationDialog] /
     * [ActionUIModel.dismissDialog] recompose the dialog host
     * ([com.abracode.actionui.Helpers.WindowDialogHost]). Mirrors the Swift
     * `@Published var windowDialog`. (The `sheet` / `fullScreenCover` modal half -
     * Swift's `windowModal` - is not ported yet.)
     */
    var windowDialog: WindowDialog? by mutableStateOf(null)

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
     * Merges [subRoot] and its descendants into this window's existing [ViewModel]
     * pool **without clearing it** - the registration path for a sub-tree loaded at
     * runtime (a [com.abracode.actionui.Views.LoadableView]'s content), so the
     * value / state API reaches the loaded controls by id *within the same window*.
     * Mirrors the Swift `loadSubViewDescription`.
     *
     * Ids must be unique across the combined tree (Apple documents the same
     * assumption); a collision overwrites the existing entry - last one wins, as in
     * [populateViewModels]. Unlike [loadDescription] it does not touch [element]
     * (the window root stays the originally-loaded document). Returns [subRoot].
     */
    fun loadSubDescription(subRoot: ActionUIElement): ActionUIElement {
        populateViewModels(subRoot, into = viewModels)
        logger.log(
            "Merged sub-description into windowUUID: $windowUUID, sub-root id: ${subRoot.id}, " +
                "pool now ${viewModels.size} view model(s)",
            LoggerLevel.verbose
        )
        return subRoot
    }

    /**
     * Recursively creates a [ViewModel] for [element] and every descendant across
     * its named containers ([ActionUIElement.subElements]: `children` and the
     * single-child `content`), seeding the initial value for value-bearing
     * elements and the initial [ViewModel.states] (e.g. a `DisclosureGroup`'s
     * `isExpanded`) from the registered builder. Elements with no explicit `id`
     * share id 0 (last one wins); the value/state API is only meaningful for
     * elements that carry a positive, unique id, as on the Apple side.
     */
    private fun populateViewModels(element: ActionUIElement, into: MutableMap<Int, ViewModel>) {
        val viewModel = ViewModel()
        viewModel.elementType = element.type
        val builder = ActionUIRegistry.lookup(element.type)
        if (builder != null) {
            if (builder.valueType != ActionUIValueType.NONE) {
                viewModel.value = builder.initialValue(element)
            }
            viewModel.states.putAll(builder.initialStates(element))
        }
        into[element.id] = viewModel

        element.subElements().forEach { populateViewModels(it, into) }
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
