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
 * ## Structural mutation and the Swift WindowModel
 *
 * Runtime structural mutation (`insertElement` / `insertRow` / `removeElement`)
 * **is** ported (see the methods below), mirroring the Swift engine: each
 * mutation writes the whole new container into the parent's
 * [ViewModel.dynamicSubviews] (Compose snapshot state) and the shared build
 * entry point merges it back, so the declaring view recomposes with no
 * per-view wiring. JSON/plist decoding stays in `ActionUI.Render` / the loaders
 * (the caller decodes; [ActionUIModel.insertElement] also offers a JSON-string
 * overload that decodes + platform-filters). [populateViewModels] recurses over
 * [ActionUIElement.subElements], which flattens every named container the model
 * supports.
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
     * Maps a parentID to the set of element ids inserted under it at runtime via
     * [insertElement] / [insertRow]. Mirrors Swift's `dynamicallyInsertedIDs`:
     * keeps the parent's id ledger across subsequent removes and lets a parent's
     * own removal cascade-clean its dynamic descendants. The live container
     * contents themselves live in [ViewModel.dynamicSubviews]; this is only the
     * cleanup ledger.
     */
    private val dynamicallyInsertedIDs: MutableMap<Int, MutableSet<Int>> = mutableMapOf()

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
     * The active window-level modal (sheet / fullScreenCover), or `null` when none
     * is presented. Backed by Compose snapshot state so [ActionUIModel.presentModal]
     * / [ActionUIModel.dismissModal] recompose the modal host
     * ([com.abracode.actionui.Helpers.WindowModalHost]). Mirrors the Swift
     * `@Published var windowModal`.
     */
    var windowModal: WindowModal? by mutableStateOf(null)

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
     * Merges a modal sub-document [modalRoot] into this window's [ViewModel] pool and
     * returns the set of element ids it **newly added**, so the caller
     * ([ActionUIModel.dismissModal]) can remove exactly those on dismiss. Ids that
     * collide with existing pool entries are skipped (with a warning) and excluded
     * from the returned set - so presenting then dismissing a modal can never evict
     * the underlying window's view models. (A safety improvement over Swift, which
     * tracks all ids and leans on the unique-id assumption; the Android merge still
     * follows Swift's conflict-skip.) Used by `presentModal`; does not touch
     * [element] (the modal is an overlay, not the window root).
     */
    fun loadModalDescription(modalRoot: ActionUIElement): Set<Int> {
        val modalViewModels = mutableMapOf<Int, ViewModel>()
        populateViewModels(modalRoot, into = modalViewModels)
        val addedIDs = mutableSetOf<Int>()
        for ((id, viewModel) in modalViewModels) {
            if (viewModels.containsKey(id)) {
                logger.log("Modal ID conflict for element $id; skipping merge", LoggerLevel.warning)
            } else {
                viewModels[id] = viewModel
                addedIDs += id
            }
        }
        logger.log(
            "Loaded modal description into windowUUID: $windowUUID, root id: ${modalRoot.id}, " +
                "added ${addedIDs.size} view model(s), pool now ${viewModels.size}",
            LoggerLevel.verbose
        )
        return addedIDs
    }

    /**
     * Recursively creates a [ViewModel] for [element] and every descendant across
     * its named containers ([ActionUIElement.subElements]: `children` and the
     * single-child `content`), seeding the initial value for value-bearing
     * elements and the initial [ViewModel.states] (e.g. a `DisclosureGroup`'s
     * `isExpanded`) from the registered builder. Only elements with a positive
     * `id` register (see the in-body comment); the value/state API is only
     * meaningful for elements that carry a positive, unique id, as on the
     * Apple side.
     */
    private fun populateViewModels(element: ActionUIElement, into: MutableMap<Int, ViewModel>) {
        // Only positive ids register - Apple's documented contract ("non-zero
        // positive integer for runtime programmatic interaction"). Elements
        // without an id default to 0 and would all collide on one map key,
        // last-one-wins: every id-less value control in the document would then
        // bind to the same ViewModel and read the last element's seeded value
        // (three id-less AsyncImages all loading the last one's url). Id-less
        // controls instead take their local-state fallback path.
        if (element.id > 0) {
            val viewModel = ViewModel()
            viewModel.elementType = element.type
            viewModel.authoredProperties = element.properties
            val builder = ActionUIRegistry.lookup(element.type)
            if (builder != null) {
                if (builder.valueType != ActionUIValueType.NONE) {
                    viewModel.value = builder.initialValue(element)
                }
                viewModel.states.putAll(builder.initialStates(element))
            }
            into[element.id] = viewModel
        }

        element.subElements().forEach { populateViewModels(it, into) }
    }

    // MARK: - Runtime structural mutations (insertElement / insertRow / removeElement)
    //
    // The Android port of the Swift `WindowModel` mutation engine. Each mutation
    // writes the whole new container contents into the parent
    // [ViewModel.dynamicSubviews] - Compose snapshot state, so the write alone
    // recomposes the parent and its child loop re-runs with the merged container
    // (the shared build entry point's `effectiveElement` merges it back over the
    // authored subviews). The authored [element] graph is never mutated. There is
    // no `objectWillChange.send()` analog: snapshot state is the change signal,
    // exactly as for the value / state / property APIs.

    /**
     * Inserts [newElement] into the flat [container] (`children` / `destinations`)
     * of the element with [parentID], at [position]. Returns the inserted id.
     * Mirrors the Swift `WindowModel.insertElement`.
     */
    fun insertElement(
        newElement: ActionUIElement,
        parentID: Int,
        container: String,
        position: InsertPosition,
    ): Int {
        val parent = locateElement(parentID) ?: throw InsertError.ParentNotFound(parentID)
        if (!viewModels.containsKey(parentID)) throw InsertError.ParentNotFound(parentID)
        val current = effectiveFlatContainer(parent, container).toMutableList()
        val index = resolveFlatIndex(current, position, container)

        val newIDs = collectAllElementIDs(newElement)
        val conflicts = newIDs.intersect(viewModels.keys)
        if (conflicts.isNotEmpty()) throw InsertError.IdConflict(conflicts.sorted())

        current.add(index, newElement)
        setDynamicContainer(parentID, container, current.toList())

        populateViewModels(newElement, into = viewModels)
        dynamicallyInsertedIDs.getOrPut(parentID) { mutableSetOf() }.addAll(newIDs)
        logger.log(
            "Inserted element id ${newElement.id} into parent $parentID.$container at index $index",
            LoggerLevel.debug,
        )
        return newElement.id
    }

    /**
     * Inserts a row of [cells] into a `rows` [container] (`Grid`), at [position]
     * (before/after are rejected - rows have no synthetic id). Returns the cell
     * ids in order. Mirrors the Swift `WindowModel.insertRow`.
     */
    fun insertRow(
        cells: List<ActionUIElement>,
        parentID: Int,
        container: String,
        position: InsertPosition,
    ): List<Int> {
        if (position is InsertPosition.Before || position is InsertPosition.After) {
            throw InsertError.UnsupportedPositionForRowContainer(container)
        }
        val parent = locateElement(parentID) ?: throw InsertError.ParentNotFound(parentID)
        if (!viewModels.containsKey(parentID)) throw InsertError.ParentNotFound(parentID)
        val current = effectiveRowsContainer(parent, container).map { it.toList() }.toMutableList()
        val index = resolveRowIndex(current, position)

        val newIDs = mutableSetOf<Int>()
        for (cell in cells) newIDs.addAll(collectAllElementIDs(cell))
        val conflicts = newIDs.intersect(viewModels.keys)
        if (conflicts.isNotEmpty()) throw InsertError.IdConflict(conflicts.sorted())

        current.add(index, cells.toList())
        setDynamicContainer(parentID, container, current.map { it.toList() })

        for (cell in cells) populateViewModels(cell, into = viewModels)
        dynamicallyInsertedIDs.getOrPut(parentID) { mutableSetOf() }.addAll(newIDs)
        logger.log(
            "Inserted row of ${cells.size} cells into parent $parentID.$container at row $index",
            LoggerLevel.debug,
        )
        return cells.map { it.id }
    }

    /**
     * Removes the element with [viewID] from its flat / rows container, cascade-
     * cleaning the view models of it and all descendants. Refuses the window root;
     * single-child containers (`content` / `sidebar` / ...) are not removable (swap
     * via property / LoadableView). For a `Grid` row, only individual cells (which
     * carry ids) are addressable. Mirrors the Swift `WindowModel.removeElement`.
     */
    fun removeElement(viewID: Int) {
        if (viewID == element?.id) throw InsertError.RootRemovalForbidden(viewID)
        if (!viewModels.containsKey(viewID)) throw InsertError.ViewNotFound(viewID)
        val location = locateParent(viewID) ?: throw InsertError.ViewNotFound(viewID)
        if (!viewModels.containsKey(location.parentID)) throw InsertError.ParentNotFound(location.parentID)

        when (location.shape) {
            ContainerShape.FLAT -> {
                val current = effectiveFlatContainer(location.parent, location.container).toMutableList()
                val idx = current.indexOfFirst { it.id == viewID }
                if (idx >= 0) {
                    current.removeAt(idx)
                    setDynamicContainer(location.parentID, location.container, current.toList())
                }
            }
            ContainerShape.ROWS -> {
                val current = effectiveRowsContainer(location.parent, location.container)
                    .map { it.toMutableList() }.toMutableList()
                val r = location.rowIndex
                val c = location.colIndex
                if (r != null && c != null && r < current.size && c < current[r].size && current[r][c].id == viewID) {
                    current[r].removeAt(c)
                    setDynamicContainer(location.parentID, location.container, current.map { it.toList() })
                }
            }
        }

        val descendantIDs = collectAllElementIDs(location.removedElement)
        for (id in descendantIDs) viewModels.remove(id)
        dynamicallyInsertedIDs[location.parentID]?.removeAll(descendantIDs)
        if (dynamicallyInsertedIDs[location.parentID]?.isEmpty() == true) {
            dynamicallyInsertedIDs.remove(location.parentID)
        }
        for (id in descendantIDs) dynamicallyInsertedIDs.remove(id)
        logger.log(
            "Removed element id $viewID from parent ${location.parentID}.${location.container}; " +
                "cleaned ${descendantIDs.size} view model(s)",
            LoggerLevel.debug,
        )
    }

    // MARK: - Effective-tree helpers

    /** Writes a container override into the parent's [ViewModel.dynamicSubviews]. */
    private fun setDynamicContainer(parentID: Int, container: String, value: Any) {
        viewModels[parentID]?.dynamicSubviews?.put(container, value)
    }

    /**
     * The live contents of a flat [container] of [parent]: the
     * [ViewModel.dynamicSubviews] override if present, else the authored field.
     */
    private fun effectiveFlatContainer(parent: ActionUIElement, container: String): List<ActionUIElement> {
        @Suppress("UNCHECKED_CAST")
        (viewModels[parent.id]?.dynamicSubviews?.get(container) as? List<ActionUIElement>)?.let { return it }
        return when (container) {
            "children" -> parent.children.orEmpty()
            "destinations" -> parent.destinations.orEmpty()
            else -> emptyList()
        }
    }

    /** The live `rows` contents of [parent]: the override if present, else authored. */
    private fun effectiveRowsContainer(parent: ActionUIElement, container: String): List<List<ActionUIElement>> {
        @Suppress("UNCHECKED_CAST")
        (viewModels[parent.id]?.dynamicSubviews?.get(container) as? List<List<ActionUIElement>>)?.let { return it }
        return parent.rows.orEmpty()
    }

    private fun resolveFlatIndex(arr: List<ActionUIElement>, position: InsertPosition, container: String): Int =
        when (position) {
            is InsertPosition.Append -> arr.size
            is InsertPosition.Prepend -> 0
            is InsertPosition.At -> {
                if (position.index < 0 || position.index > arr.size) {
                    throw InsertError.PositionOutOfBounds(position.index, arr.size)
                }
                position.index
            }
            is InsertPosition.Before -> {
                val idx = arr.indexOfFirst { it.id == position.siblingID }
                if (idx < 0) throw InsertError.SiblingNotFound(position.siblingID, container)
                idx
            }
            is InsertPosition.After -> {
                val idx = arr.indexOfFirst { it.id == position.siblingID }
                if (idx < 0) throw InsertError.SiblingNotFound(position.siblingID, container)
                idx + 1
            }
        }

    private fun resolveRowIndex(rows: List<List<ActionUIElement>>, position: InsertPosition): Int =
        when (position) {
            is InsertPosition.Append -> rows.size
            is InsertPosition.Prepend -> 0
            is InsertPosition.At -> {
                if (position.index < 0 || position.index > rows.size) {
                    throw InsertError.PositionOutOfBounds(position.index, rows.size)
                }
                position.index
            }
            is InsertPosition.Before, is InsertPosition.After ->
                throw InsertError.UnsupportedPositionForRowContainer("rows")
        }

    /**
     * Every positive element id within [element]'s subtree (itself + descendants
     * across all registered containers; the per-row `template` excepted, as in
     * [populateViewModels]). Used for id-conflict checks and cascade cleanup.
     */
    private fun collectAllElementIDs(element: ActionUIElement): Set<Int> {
        val ids = mutableSetOf<Int>()
        fun walk(e: ActionUIElement) {
            if (e.id > 0) ids.add(e.id)
            e.subElements().forEach { walk(it) }
        }
        walk(element)
        return ids
    }

    /** Single-child / toolbar members - the non-insertable containers, walked for nested-parent lookup. */
    private fun nonInsertableSubElements(e: ActionUIElement): List<ActionUIElement> = buildList {
        e.content?.let { add(it) }
        e.destination?.let { add(it) }
        e.sidebar?.let { add(it) }
        e.detail?.let { add(it) }
        e.toolbar?.let { addAll(it) }
        e.sheet?.let { add(it) }
        e.fullScreenCover?.let { add(it) }
        e.popover?.let { add(it) }
        e.overlay?.let { add(it) }
        e.background?.let { add(it) }
    }

    /** Finds an element by id in the effective tree (override-aware), or null. */
    private fun locateElement(id: Int): ActionUIElement? {
        val root = element ?: return null
        return locateElementHelper(root, id)
    }

    private fun locateElementHelper(element: ActionUIElement, id: Int): ActionUIElement? {
        if (element.id == id) return element
        for (child in effectiveFlatContainer(element, "children")) {
            locateElementHelper(child, id)?.let { return it }
        }
        for (child in effectiveFlatContainer(element, "destinations")) {
            locateElementHelper(child, id)?.let { return it }
        }
        for (row in effectiveRowsContainer(element, "rows")) {
            for (child in row) locateElementHelper(child, id)?.let { return it }
        }
        for (child in nonInsertableSubElements(element)) {
            locateElementHelper(child, id)?.let { return it }
        }
        return null
    }

    /** Where a child lives in the effective tree: its owning flat / rows container. */
    private data class ParentLocation(
        val parent: ActionUIElement,
        val parentID: Int,
        val container: String,
        val shape: ContainerShape,
        val rowIndex: Int?,
        val colIndex: Int?,
        val removedElement: ActionUIElement,
    )

    private fun locateParent(childID: Int): ParentLocation? {
        val root = element ?: return null
        return locateParentHelper(root, childID)
    }

    private fun locateParentHelper(element: ActionUIElement, childID: Int): ParentLocation? {
        for (container in listOf("children", "destinations")) {
            val list = effectiveFlatContainer(element, container)
            list.firstOrNull { it.id == childID }?.let {
                return ParentLocation(element, element.id, container, ContainerShape.FLAT, null, null, it)
            }
            for (child in list) locateParentHelper(child, childID)?.let { return it }
        }
        val rows = effectiveRowsContainer(element, "rows")
        for (r in rows.indices) {
            for (c in rows[r].indices) {
                if (rows[r][c].id == childID) {
                    return ParentLocation(element, element.id, "rows", ContainerShape.ROWS, r, c, rows[r][c])
                }
            }
        }
        for (row in rows) {
            for (child in row) locateParentHelper(child, childID)?.let { return it }
        }
        for (child in nonInsertableSubElements(element)) {
            // A single-element / toolbar member is not removable via removeElement.
            if (child.id == childID) return null
            locateParentHelper(child, childID)?.let { return it }
        }
        return null
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
