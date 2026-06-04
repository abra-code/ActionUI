package com.abracode.actionui.Common

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * Base shape of a decoded ActionUI element.
 *
 * ## Named containers
 *
 * SwiftUI's `ActionUIElement` stores every nested view under a stringly-typed
 * `subviews: [String: Any]?` dictionary whose keys are *named containers* - some
 * holding an **array** of elements (`children`, `destinations`, `toolbar`,
 * `commands`, and `rows` as an array-of-arrays) and some a **single** child
 * element (`content`, `destination`, `sidebar`, `detail`, `label`, `popover`,
 * `template`, `sheet`, `fullScreenCover`, `overlay`, `background`). See
 * `ActionUI/Common/ActionUIElement.swift`.
 *
 * Android models these as explicit, typed fields rather than one untyped map:
 * it is idiomatic Kotlin, decodes natively with `kotlinx.serialization` (a JSON
 * array -> `List<ActionUIElement>`, a JSON object -> `ActionUIElement`), and the
 * existing renderer already reads `element.children` directly everywhere. New
 * named containers are added here one field at a time, as the elements that use
 * them are ported - the same incremental stance the rest of the port takes.
 *
 * Implemented so far:
 *   * [children] - the array container (stacks, Group, ...).
 *   * [content]  - the first **single-child** container (ScrollView, and the
 *     coming GroupBox / LabeledContent / DisclosureGroup family). A single child,
 *     never an array on Android: author multiple children by wrapping them in a
 *     `VStack` / `Group`.
 *
 * Any traversal of the element tree (id registration, etc.) should iterate
 * [subElements] so it automatically covers every named container as more are
 * added.
 */
interface ActionUIElementBase {
    val id: Int
    val type: String
    val properties: JsonObject?
    val children: List<ActionUIElement>?
    val content: ActionUIElement?
}

@Serializable
data class ActionUIElement(
    override val id: Int = 0,
    override val type: String = "",
    override val properties: JsonObject? = null,
    override val children: List<ActionUIElement>? = null,
    override val content: ActionUIElement? = null
) : ActionUIElementBase

/**
 * Every directly-contained child element, flattened across all named containers
 * in a stable order, for tree traversal (e.g. seeding view models by id). Add
 * each new single-child / array container here so existing walks pick it up
 * without change.
 */
fun ActionUIElement.subElements(): List<ActionUIElement> = buildList {
    children?.let { addAll(it) }
    content?.let { add(it) }
}
