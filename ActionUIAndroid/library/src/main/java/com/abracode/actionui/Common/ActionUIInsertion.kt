package com.abracode.actionui.Common

/**
 * Types and errors for the runtime structural-mutation API
 * ([ActionUIModel.insertElement] / [ActionUIModel.insertRow] /
 * [ActionUIModel.removeElement]). The Android counterpart of Swift's
 * `Common/ActionUIInsertion.swift`.
 *
 * Containers declare which of their named subview containers accept runtime
 * insertions via [ActionUIViewConstruction.insertableContainers]; the model
 * resolves a request against that map ([ContainerShape] picks the method) and
 * mutates the parent [ViewModel.dynamicSubviews] override that the shared build
 * entry point merges back in. See [WindowModel] for the mutation engine.
 */

/**
 * Position to insert a new element (or row) within a container's existing array.
 * [Before] / [After] apply only to flat containers - for row containers, rows
 * have no synthetic identity, so use [At], [Append], or [Prepend].
 */
sealed class InsertPosition {
    /** Insert at the end of the container. */
    object Append : InsertPosition()

    /** Insert at the front of the container. */
    object Prepend : InsertPosition()

    /** Insert at an explicit index (0..count). */
    data class At(val index: Int) : InsertPosition()

    /** Insert immediately before the flat-container sibling with this id. */
    data class Before(val siblingID: Int) : InsertPosition()

    /** Insert immediately after the flat-container sibling with this id. */
    data class After(val siblingID: Int) : InsertPosition()
}

/**
 * Shape of an insertable container: a flat array of elements (`children`,
 * `destinations`) or a 2-D array of element rows (`Grid`'s `rows`). Determines
 * whether [ActionUIModel.insertElement] (flat) or [ActionUIModel.insertRow]
 * (rows) applies.
 */
enum class ContainerShape { FLAT, ROWS }

/**
 * Errors thrown by [ActionUIModel.insertElement] / [ActionUIModel.insertRow] /
 * [ActionUIModel.removeElement]. One [Exception] subclass per Apple
 * `InsertError` case, with the same human-readable messages (ASCII hyphens in
 * place of Apple's em dashes, per the project's ASCII-only source rule).
 */
sealed class InsertError(message: String) : Exception(message) {
    class WindowNotFound(uuid: String) :
        InsertError("No WindowModel for windowUUID: $uuid")

    class ParentNotFound(parentID: Int) :
        InsertError("No element found with parentID $parentID")

    class NotAContainer(type: String) :
        InsertError("Element type '$type' does not accept insertions (no insertableContainers declared)")

    class UnknownContainer(container: String, validContainers: List<String>) :
        InsertError("Unknown container '$container'. Valid containers: ${validContainers.joinToString(", ")}")

    class ContainerRequired(validContainers: List<String>) :
        InsertError("container is required when the element exposes multiple containers: ${validContainers.joinToString(", ")}")

    class WrongMethod(container: String, expectedShape: ContainerShape, detail: String) :
        InsertError("Container '$container' has shape $expectedShape; $detail")

    class UnsupportedPositionForRowContainer(container: String) :
        InsertError("Row container '$container' does not support before/after sibling positions; rows have no addressable identity")

    class PositionOutOfBounds(index: Int, count: Int) :
        InsertError("Position $index is out of bounds for container of size $count")

    class SiblingNotFound(siblingID: Int, container: String) :
        InsertError("No element with id $siblingID found in container '$container'")

    class IdConflict(ids: List<Int>) :
        InsertError("ID conflict - elements with these IDs are already registered: $ids")

    class InvalidJSON(detail: String) :
        InsertError("Invalid JSON: $detail")

    object MissingType :
        InsertError("Element dictionary missing 'type' key")

    class RootRemovalForbidden(rootID: Int) :
        InsertError("Cannot remove root element (id $rootID)")

    class ViewNotFound(viewID: Int) :
        InsertError("No element found with viewID $viewID")

    class ViewIsRowMember(viewID: Int) :
        InsertError("viewID $viewID is a Grid cell - removing it removes only the cell, not its row. Rows are not addressable by id.")
}
