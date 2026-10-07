package com.abracode.actionui.Helpers

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.ViewModel
import com.abracode.actionui.Common.applyCommonProperties
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Shared infrastructure for the data-driven repeater (`template`) containers -
 * the Android counterpart of Swift's `Helpers/TemplateHelper.swift`.
 *
 * When a container (`List`, `Section`) declares a [ActionUIElement.template]
 * instead of (or alongside) `children`, it renders one instance of the template
 * per row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (a `List<List<String>>`,
 * set through the rows API). String properties in the template carry 1-based
 * column references that are substituted per row:
 *
 *   * `$0`  -> all columns joined with ", "
 *   * `$1`  -> column 0 (first column)
 *   * `$2`  -> column 1
 *   * `$N`  -> column N-1
 *
 * **How the per-row view is built (the load-bearing difference vs. Swift).**
 * Swift sets a `templateContext` on a throw-away `ViewModel` and lets container
 * views re-enter `TemplateHelper` for their children. Android instead does the
 * substitution **eagerly over the whole template subtree** ([substituteElement]
 * walks `properties` + `children` + `content`) and then renders the substituted
 * copy through the normal registry pipeline. A substituted container therefore
 * already holds substituted children, so no per-container special-casing is
 * needed. The one piece of context a leaf still needs - which `List`/`Section`
 * owns it and at which row, for action dispatch - is carried by
 * [LocalTemplateContext] (read by `Button` and `Toggle`).
 *
 * **Boolean properties from row data.** `isOn`, `disabled` and `hidden` written as
 * a string in a template are read as a Boolean after substitution ([rowBool]):
 * "true" or "1" is on, "false", "0" or an empty string is off, in any letter case;
 * any other text is off, with one warning. The same rule as Swift and Web.
 *
 * **Row-bound Toggle.** The row data is the source of truth for a `Toggle` in a
 * template. When its `isOn` is exactly one column reference (`$N`), the substituted
 * copy carries that column as the internal [IS_ON_COLUMN_KEY] property (a name no
 * schema property can have), and a user toggle writes "true" or "false" into that
 * cell of the container's rows before its `actionID` fires ([commitRowToggle]). Any
 * other `isOn` leaves the Toggle display-only.
 *
 * **Substitution is single-pass and multi-digit-safe.** A regex replaces every
 * `$N` in one sweep, so a column whose value itself contains `$2` is not
 * re-substituted, and `$12` is read as column 12 (not `$1` then a literal `2`).
 * This is a deliberate refinement over Swift's sequential
 * `replacingOccurrences`; an out-of-range `$N` is left as the literal text, as
 * on Swift.
 */
object TemplateHelper {

    private val COLUMN_REF = Regex("""\$(\d+)""")
    private val SINGLE_COLUMN_REF = Regex("""^\$(\d+)$""")

    /** The properties a template may give as a string, read as a Boolean after substitution. */
    private val ROW_BOOL_KEYS = listOf("isOn", "disabled", "hidden")

    /** The internal property a substituted `Toggle` carries when its `isOn` names one column. */
    const val IS_ON_COLUMN_KEY = "\$isOnColumn"

    /**
     * Reads row text as a Boolean: "true" or "1" is on, "false", "0" or "" is off, in
     * any letter case. Returns `null` for any other text (the caller treats it as off).
     */
    fun rowBool(text: String): Boolean? = when (text.lowercase()) {
        "true", "1" -> true
        "false", "0", "" -> false
        else -> null
    }

    /** The text a toggled cell stores. */
    fun rowBoolText(flag: Boolean): String = if (flag) "true" else "false"

    /**
     * The 0-based column a property names when it is exactly one column reference
     * (`$N`, N of 1 or more), else `null`. `$0` (all columns) does not name one column.
     */
    fun singleColumnIndex(value: JsonElement?): Int? {
        val primitive = value as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        val n = SINGLE_COLUMN_REF.matchEntire(primitive.content)?.groupValues?.get(1)?.toIntOrNull() ?: return null
        return if (n >= 1) n - 1 else null
    }

    private val warned = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    /**
     * Logs a warning the first time it is seen: a template composes once per row on
     * every refresh, so a per-row warning would otherwise repeat without end.
     */
    fun warnOnce(message: String, logger: ActionUILogger?) {
        if (warned.add(message)) logger?.log(message, LoggerLevel.warning)
    }

    /**
     * The properties of one template instance: [properties] with the column references
     * substituted from [row], the Boolean properties written as a string ([ROW_BOOL_KEYS])
     * read from the row as a Boolean, and, for a `Toggle` whose `isOn` names one column,
     * that column under [IS_ON_COLUMN_KEY].
     */
    fun instanceProperties(
        type: String,
        properties: JsonObject,
        row: List<String>,
        logger: ActionUILogger? = null,
    ): JsonObject {
        val substituted = (substituteJson(properties, row) as JsonObject).toMutableMap()
        for (key in ROW_BOOL_KEYS) {
            val raw = properties[key] as? JsonPrimitive ?: continue
            if (!raw.isString) continue
            val text = (substituted[key] as? JsonPrimitive)?.content ?: continue
            val flag = rowBool(text)
            if (flag == null) {
                warnOnce("$type $key '$text' in a template row is not a Boolean (true, false, 1, 0 or empty); treating as false", logger)
            }
            substituted[key] = JsonPrimitive(flag ?: false)
        }
        if (type == "Toggle") {
            singleColumnIndex(properties["isOn"])?.let { substituted[IS_ON_COLUMN_KEY] = JsonPrimitive(it) }
        }
        return JsonObject(substituted)
    }

    /**
     * Writes [text] into one cell of the rows held by [container] (the owning
     * container's view model) after a user edit of a row-bound control. The row is the
     * one drawn at [rowIndex] when it is still [drawnRow], else the first equal row; a
     * row shorter than [column] is padded with empty strings. A selection resting on
     * that row follows it, so the write loses no highlight and fires no selection
     * action. Returns the index of the row written, or `null` when the row is gone.
     */
    fun writeRowCell(container: ViewModel, drawnRow: List<String>, rowIndex: Int, column: Int, text: String): Int? {
        if (column < 0) return null
        @Suppress("UNCHECKED_CAST")
        val rows = (container.states[ActionUIModel.ROWS_STATE_KEY] as? List<List<String>>) ?: return null
        val index = if (rows.getOrNull(rowIndex) == drawnRow) rowIndex else rows.indexOf(drawnRow)
        if (index < 0) return null
        val oldRow = rows[index]
        val newRow = oldRow.toMutableList()
        while (newRow.size <= column) newRow.add("")
        newRow[column] = text
        container.states[ActionUIModel.ROWS_STATE_KEY] = rows.toMutableList().also { it[index] = newRow }
        val selected = container.value as? List<*>
        if (selected != null && selected.isNotEmpty() && selected == oldRow) container.value = newRow
        return index
    }

    /**
     * A user toggle of a `Toggle` in a template row: writes the new state into the row
     * (when [column] names one) and then fires [actionID] with the container's id, the
     * row index and the new Boolean, so a handler that reads the rows sees the new
     * value. Without a column the Toggle is display-only and nothing happens. Returns
     * whether the toggle was taken.
     */
    fun commitRowToggle(
        isOn: Boolean,
        container: ViewModel?,
        context: TemplateContext,
        column: Int?,
        actionID: String?,
    ): Boolean {
        if (container == null || column == null) return false
        val index = writeRowCell(container, context.row, context.rowIndex, column, rowBoolText(isOn)) ?: return false
        if (actionID != null) {
            ActionUIModel.actionHandler(actionID, viewID = context.parentID, viewPartID = index, context = isOn)
        }
        return true
    }

    /**
     * Substitutes `$0`/`$1`/`$N` column references in [template] against [row].
     * `$0` joins all columns with ", "; `$N` (1-based) maps to `row[N-1]`; an
     * out-of-range index is left as its literal `$N` text.
     */
    fun substituteString(template: String, row: List<String>): String =
        COLUMN_REF.replace(template) { match ->
            when (val n = match.groupValues[1].toInt()) {
                0 -> row.joinToString(", ")
                else -> row.getOrNull(n - 1) ?: match.value
            }
        }

    /**
     * Recursively rebuilds [element], substituting column references in every
     * **string** primitive (numbers/booleans/null pass through unchanged), so
     * the substitution reaches strings nested in objects and arrays.
     */
    fun substituteJson(element: JsonElement, row: List<String>): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.mapValues { substituteJson(it.value, row) })
        is JsonArray -> JsonArray(element.map { substituteJson(it, row) })
        // JsonPrimitive covers JsonNull too; only string primitives are substituted.
        is JsonPrimitive ->
            if (element.isString) JsonPrimitive(substituteString(element.content, row)) else element
    }

    /**
     * Returns a copy of [template] with column references substituted across its
     * `properties`, `children`, and `content` for the given [row]. The nested
     * `template` field (if any) is left untouched.
     */
    fun substituteElement(
        template: ActionUIElement,
        row: List<String>,
        logger: ActionUILogger? = null,
    ): ActionUIElement =
        template.copy(
            properties = template.properties?.let { instanceProperties(template.type, it, row, logger) },
            children = template.children?.map { substituteElement(it, row, logger) },
            content = template.content?.let { substituteElement(it, row, logger) },
        )

    /**
     * Renders one template instance for [row]. Substitutes the subtree, looks up
     * the (substituted) root builder, provides a [LocalTemplateContext] so a
     * `Button` in the template dispatches with the owning container's id as
     * `viewID` and [rowIndex] as `viewPartID` (the Swift action convention), and
     * builds it through the registry with the inherited text-style environment
     * and the universal modifiers. Renders nothing if the type is unregistered.
     * [baseModifier] is prepended to the instance's own modifier; `Group` uses it
     * to apply its group-level modifier to each row, the way it does to children.
     */
    @Composable
    fun BuildTemplateRow(
        template: ActionUIElement,
        row: List<String>,
        parentID: Int,
        rowIndex: Int,
        baseModifier: Modifier = Modifier,
    ) {
        val logger = LocalActionUILogger.current
        val substituted = substituteElement(template, row, logger)
        val builder = ActionUIRegistry.lookup(substituted.type) ?: return
        CompositionLocalProvider(LocalTemplateContext provides TemplateContext(parentID, rowIndex, row)) {
            // Template rows build through BuildView directly (not BuildViewWithModifiers), so the
            // runtime-reactive environment normally provided there is provided here too, off the
            // substituted row properties: foregroundStyle/tint and disabled/hidden, all via the
            // single ProvideReactiveEnvironment (ReactiveEnvironment.kt). disabled/hidden given as
            // a column reference were read from the row as a Boolean by substituteElement, so
            // they can differ per row.
            ProvideTextStyleEnvironment(substituted.properties, logger) {
                ProvideReactiveEnvironment(substituted.properties, logger) {
                    builder.BuildView(substituted, baseModifier.then(Modifier.applyCommonProperties(substituted.properties, logger, MaterialTheme.colorScheme)))
                }
            }
        }
    }
}

/**
 * The current template row's context, or `null` outside a template. Carries the
 * owning container's element id and the 0-based row index so a `Button` inside a
 * template dispatches its action with `viewID = parentID`, `viewPartID = rowIndex`
 * - the same convention as Swift's `TemplateContext`. [row] is the row the instance
 * was built from, which a row-bound control (`Toggle`) writes its new state into.
 */
data class TemplateContext(val parentID: Int, val rowIndex: Int, val row: List<String> = emptyList())

/** CompositionLocal carrying the active [TemplateContext]; `null` outside a template row. */
val LocalTemplateContext: ProvidableCompositionLocal<TemplateContext?> =
    staticCompositionLocalOf { null }

/**
 * Reads the rows backing the data-driven element [elementID] from its bound
 * [com.abracode.actionui.Common.ViewModel] in the active window, or an empty
 * list when there is no window, no matching id, or no rows set yet. Reading the
 * snapshot-state map inside composition subscribes the caller, so a host
 * `setElementRows(...)` recomposes the `List` / `Section`.
 */
@Suppress("UNCHECKED_CAST")
@Composable
fun templateRows(elementID: Int): List<List<String>> {
    val viewModel = LocalWindowModel.current?.viewModels?.get(elementID) ?: return emptyList()
    return (viewModel.states[ActionUIModel.ROWS_STATE_KEY] as? List<List<String>>) ?: emptyList()
}
