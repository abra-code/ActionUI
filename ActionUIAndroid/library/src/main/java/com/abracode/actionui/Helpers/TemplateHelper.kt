package com.abracode.actionui.Helpers

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
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
 * [LocalTemplateContext] (read by `Button`).
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
    fun substituteElement(template: ActionUIElement, row: List<String>): ActionUIElement =
        template.copy(
            properties = template.properties?.let { substituteJson(it, row) as JsonObject },
            children = template.children?.map { substituteElement(it, row) },
            content = template.content?.let { substituteElement(it, row) },
        )

    /**
     * Renders one template instance for [row]. Substitutes the subtree, looks up
     * the (substituted) root builder, provides a [LocalTemplateContext] so a
     * `Button` in the template dispatches with the owning container's id as
     * `viewID` and [rowIndex] as `viewPartID` (the Swift action convention), and
     * builds it through the registry with the inherited text-style environment
     * and the universal modifiers. Renders nothing if the type is unregistered.
     */
    @Composable
    fun BuildTemplateRow(template: ActionUIElement, row: List<String>, parentID: Int, rowIndex: Int) {
        val logger = LocalActionUILogger.current
        val substituted = substituteElement(template, row)
        val builder = ActionUIRegistry.lookup(substituted.type) ?: return
        CompositionLocalProvider(LocalTemplateContext provides TemplateContext(parentID, rowIndex)) {
            ProvideTextStyleEnvironment(substituted.properties, logger) {
                builder.BuildView(substituted, Modifier.applyCommonProperties(substituted.properties, logger))
            }
        }
    }
}

/**
 * The current template row's context, or `null` outside a template. Carries the
 * owning container's element id and the 0-based row index so a `Button` inside a
 * template dispatches its action with `viewID = parentID`, `viewPartID = rowIndex`
 * - the same convention as Swift's `TemplateContext`.
 */
data class TemplateContext(val parentID: Int, val rowIndex: Int)

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
