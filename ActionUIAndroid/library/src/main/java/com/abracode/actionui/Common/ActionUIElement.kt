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
 *     GroupBox / LabeledContent / DisclosureGroup family). A single child,
 *     never an array on Android: author multiple children by wrapping them in a
 *     `VStack` / `Group`.
 *   * [template] - the data-driven repeater container (`List`, `Section`): a
 *     single element rendered once per data row, with `$1`/`$2`/`$0` column
 *     substitution (see `Helpers/TemplateHelper.kt`). Unlike [children] /
 *     [content] it is **excluded from [subElements]**: a template is instanced
 *     per row through throw-away rendering, not registered once in the window's
 *     [ViewModel] pool, so its own id (and its descendants') must not collide
 *     with the rest of the tree. Mirrors Swift, where template instances use
 *     throw-away `ViewModel`s rather than the window pool.
 *   * [destination] - a `NavigationLink`'s inline push target (a single view).
 *   * [destinations] - a `NavigationStack`'s array of push targets, each
 *     addressed by its `id` via a link/row's `destinationViewId`. Both
 *     navigation containers are registered (included in [subElements]) so their
 *     descendants get [ViewModel]s and are host-addressable.
 *   * [sidebar] / [detail] - a `NavigationSplitView`'s two single-child panes
 *     (the list pane and the detail pane). Registered (in [subElements]); the
 *     detail pane is driven by the sidebar selection (`destinationViewId` ->
 *     `destinations`) on tablets/foldables, collapsing to one pane on phones.
 *   * [toolbar] - the array of `ToolbarItem`/`ToolbarItemGroup` declared on any
 *     element; consumed by the navigation screen's `ToolbarHost` (Scaffold top/
 *     bottom bar), not rendered inline. Registered (in [subElements]) so each
 *     item's `content`/`children` get [ViewModel]s.
 *   * [sheet] / [fullScreenCover] - the element-level modal subviews any element
 *     may declare; presented by `Helpers/ElementModalHost.kt` when the carrier's
 *     `states["sheetVisible"]` / `states["fullScreenCoverVisible"]` flips true,
 *     not rendered inline. Registered (in [subElements]) so the modal content's
 *     controls get [ViewModel]s and are host-addressable, like on Apple.
 *   * [rows] - `Grid`'s array-of-arrays container: each inner array is one
 *     grid row's cells, in column order. Registered (flattened into
 *     [subElements]) so cells get [ViewModel]s like any other child.
 *
 * Any traversal of the element tree (id registration, etc.) should iterate
 * [subElements] so it automatically covers every named container as more are
 * added (the per-row [template] excepted, by design).
 */
interface ActionUIElementBase {
    val id: Int
    val type: String
    val properties: JsonObject?
    val children: List<ActionUIElement>?
    val content: ActionUIElement?
    val template: ActionUIElement?
    val destination: ActionUIElement?
    val destinations: List<ActionUIElement>?
    val sidebar: ActionUIElement?
    val detail: ActionUIElement?
    val toolbar: List<ActionUIElement>?
    val sheet: ActionUIElement?
    val fullScreenCover: ActionUIElement?
    val rows: List<List<ActionUIElement>>?
}

@Serializable
data class ActionUIElement(
    override val id: Int = 0,
    override val type: String = "",
    override val properties: JsonObject? = null,
    override val children: List<ActionUIElement>? = null,
    override val content: ActionUIElement? = null,
    override val template: ActionUIElement? = null,
    override val destination: ActionUIElement? = null,
    override val destinations: List<ActionUIElement>? = null,
    override val sidebar: ActionUIElement? = null,
    override val detail: ActionUIElement? = null,
    override val toolbar: List<ActionUIElement>? = null,
    override val sheet: ActionUIElement? = null,
    override val fullScreenCover: ActionUIElement? = null,
    override val rows: List<List<ActionUIElement>>? = null
) : ActionUIElementBase

/**
 * Every directly-contained child element, flattened across all named containers
 * in a stable order, for tree traversal (e.g. seeding view models by id). Add
 * each new single-child / array container here so existing walks pick it up
 * without change. The [template] container is intentionally **not** included:
 * its instances are rendered per row and never registered in the window pool.
 */
fun ActionUIElement.subElements(): List<ActionUIElement> = buildList {
    children?.let { addAll(it) }
    content?.let { add(it) }
    destination?.let { add(it) }
    destinations?.let { addAll(it) }
    sidebar?.let { add(it) }
    detail?.let { add(it) }
    toolbar?.let { addAll(it) }
    sheet?.let { add(it) }
    fullScreenCover?.let { add(it) }
    rows?.forEach { addAll(it) }
}
