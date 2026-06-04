package com.abracode.actionui.Views

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Button as M3Button
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.stringProperty
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.JsonObject

/**
 * Scrollable list. Mirror of the Apple `List` element (`ActionUI/Views/List.swift`),
 * which wraps `SwiftUI.List`. Like [LazyVStack] it maps to a Compose [LazyColumn]
 * - both the lazy builder and the scroll viewport in one - so it needs a bounded
 * height (an inherited `frame.height` wins, else [DEFAULT_MAIN_EXTENT]; the same
 * "always a finite viewport" stance the lazy stacks take).
 *
 * Three modes, resolved in the same precedence as Swift:
 *
 *   1. **Template (data-driven repeater)** - when a [ActionUIElement.template] is
 *      present: one substituted template instance per row in
 *      `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API), with
 *      `$1`/`$2`/`$0` column substitution. See `Helpers/TemplateHelper.kt`.
 *   2. **Heterogeneous (children)** - when `children` are present: each child is a
 *      full ActionUI view, built through the registry. This is the only mode that
 *      renders from a static document (no host data needed).
 *   3. **Homogeneous (itemType)** - otherwise: each row renders its first column
 *      via [resolveItemType]. `Text` (default) and `Button` are supported;
 *      `Button` fires its `itemType.actionID` with the row's value (or index,
 *      when `actionContext` is `"rowIndex"`) as context.
 *
 * The rows are seeded empty via [initialStates] so a host can address them by id
 * before data arrives (the element needs a positive `id`, as on Apple).
 *
 * **Deferred vs. Apple (documented).**
 *   * **Selection / value.** Swift exposes the selected row as a `[String]`
 *     `value` and fires the list-level `actionID` on selection change. The
 *     `[String]` value type is the value-bridge extension track (B6), so list
 *     selection - and the list-level `actionID` - are not wired yet; per-row
 *     `Button` actions (template and homogeneous) work today.
 *   * **`listStyle`** and the `listRow*` styling (background / separator / insets)
 *     are accepted in the schema but not honored here (no portable Compose
 *     `List` styling surface); they are ignored silently.
 *
 * Named `ListView` (not `List`) so the type does not shadow `kotlin.collections.List`
 * across the `Views` package; it is registered under the canonical string `"List"`.
 */
object ListView : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = element.properties
        val template = element.template
        val children = element.children.orEmpty()

        // A LazyColumn is its own scroll viewport and needs a bounded height; an
        // inherited frame.height wins, else a default keeps an unbounded parent
        // from crashing it (same guard as LazyVStack).
        val hasExplicitHeight = (props?.get("frame") as? JsonObject)?.get("height") != null
        val listModifier = if (hasExplicitHeight) modifier else modifier.height(DEFAULT_MAIN_EXTENT)

        when {
            template != null -> {
                val rows = templateRows(element.id)
                LazyColumn(modifier = listModifier) {
                    itemsIndexed(rows) { index, row ->
                        TemplateHelper.BuildTemplateRow(
                            template = template, row = row, parentID = element.id, rowIndex = index,
                        )
                    }
                }
            }

            children.isNotEmpty() -> {
                LazyColumn(modifier = listModifier) {
                    items(children) { child ->
                        val builder = ActionUIRegistry.lookup(child.type) ?: return@items
                        ProvideTextStyleEnvironment(child.properties, logger) {
                            builder.BuildView(child, Modifier.applyCommonProperties(child.properties, logger))
                        }
                    }
                }
            }

            else -> {
                val rows = templateRows(element.id)
                val itemType = resolveItemType(props, logger)
                LazyColumn(modifier = listModifier) {
                    itemsIndexed(rows) { index, row ->
                        HomogeneousRow(itemType, row.firstOrNull().orEmpty(), index, element.id)
                    }
                }
            }
        }
    }

    /** Default scroll-viewport height when JSON supplies no `frame.height`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp
}

/**
 * Resolved homogeneous `itemType`. [viewType] is narrowed to what the Android
 * renderer draws today - `"Text"` or `"Button"`; `Image`/`AsyncImage` cells
 * downgrade to `Text` (the image-resolution contract is the B2 track).
 */
internal data class ListItemType(
    val viewType: String,
    val actionContext: String,
    val actionID: String?,
)

/**
 * Resolves the `itemType` object for homogeneous mode, defaulting to a `Text`
 * cell and warning (matching Swift's validator) on an unknown `viewType` or
 * `actionContext`. `Image`/`AsyncImage` warn and render as text (B2). Pure
 * (logging aside) so it is unit-testable.
 */
internal fun resolveItemType(props: JsonObject?, logger: ActionUILogger): ListItemType {
    val itemType = props?.get("itemType") as? JsonObject

    val viewType = when (val raw = itemType?.stringProperty("viewType") ?: "Text") {
        "Text", "Button" -> raw
        "Image", "AsyncImage" -> {
            logger.log(
                "List itemType.viewType '$raw' renders as text on Android (image contract deferred, B2)",
                LoggerLevel.warning,
            )
            "Text"
        }
        else -> {
            logger.log("List itemType.viewType '$raw' invalid; defaulting to Text", LoggerLevel.warning)
            "Text"
        }
    }

    val actionContext = when (val raw = itemType?.stringProperty("actionContext")) {
        null, "title", "rowIndex" -> raw ?: "title"
        else -> {
            logger.log("List itemType.actionContext '$raw' invalid; defaulting to title", LoggerLevel.warning)
            "title"
        }
    }

    return ListItemType(viewType, actionContext, itemType?.stringProperty("actionID"))
}

/**
 * One homogeneous row. A `Text` cell shows the value; a `Button` cell fires its
 * `itemType.actionID` with the owning list id as `viewID`, the row index as
 * `viewPartID`, and the value (or the index, for `actionContext == "rowIndex"`)
 * as context.
 */
@Composable
private fun HomogeneousRow(itemType: ListItemType, value: String, index: Int, parentID: Int) {
    when (itemType.viewType) {
        "Button" -> M3Button(
            onClick = {
                itemType.actionID?.let { actionID ->
                    val context: Any = if (itemType.actionContext == "rowIndex") index else value
                    ActionUIModel.actionHandler(
                        actionID, viewID = parentID, viewPartID = index, context = context,
                    )
                }
            }
        ) { M3Text(text = value) }
        else -> M3Text(text = value)
    }
}
