package com.abracode.actionui.Views

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button as M3Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.LocalActionUIInputEnabled
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.RefreshableScrollContainer
import com.abracode.actionui.Helpers.RegisterLazyScrollHandle
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.applyScrollContentBackground
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
 * **Selection (value bridge, B6).** Like Apple, the selected row is exposed as the
 * element's [ActionUIValueType.STRING_LIST] `value` - the selected row's columns
 * (empty when nothing is selected) - so a host reads it with
 * `ActionUIModel.getElementValueAsString` (tab-joined) and writes it with
 * `setElementValueFromString`. Selection is **interactive only when a list-level
 * `actionID` is present** (Apple's selectable mode): in the data-row modes
 * (template / homogeneous) a tap selects the row, stores it as the value,
 * highlights it, and fires `actionID` with the row as `context`. Single-selection
 * only. Per-row `Button` actions still fire independently (the inner control
 * consumes its own tap).
 *
 * **Pull-to-refresh.** When the element carries an `onRefreshActionID`, the LazyColumn is
 * wrapped in a Material3 pull-to-refresh box (see [RefreshableScrollContainer]); a pull fires
 * the actionID and the indicator stays until the client delivers fresh rows. Apple parity is
 * the `.refreshable` modifier on the same element.
 *
 * **Deferred vs. Apple (documented).**
 *   * **Children-mode selection.** Heterogeneous `children` are arbitrary,
 *     possibly-interactive views, so wrapping each in a selection surface would
 *     fight their own taps (the conflict Apple sidesteps by requiring Label/Text
 *     children under `List(selection:)`). Children mode keeps its children
 *     interactive and is not row-selectable; the value bridge is still live, so a
 *     host can set/read the selection programmatically.
 *   * **`listStyle`** and the `listRow*` styling (background / separator / insets)
 *     are accepted in the schema but not honored here (no portable Compose
 *     `List` styling surface); they are ignored silently.
 *
 * Named `ListView` (not `List`) so the type does not shadow `kotlin.collections.List`
 * across the `Views` package; it is registered under the canonical string `"List"`.
 */
object ListView : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    /** The selected row, as the Apple-parity `[String]` selection value. */
    override val valueType = ActionUIValueType.STRING_LIST

    /** Nothing selected initially (matches Apple's empty `[String]` default). */
    override fun initialValue(element: ActionUIElement): Any? = emptyList<String>()

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
        val listModifier = (if (hasExplicitHeight) modifier else modifier.height(DEFAULT_MAIN_EXTENT))
            .applyScrollContentBackground(props, logger)

        // Selection (value bridge): interactive only when a list-level actionID is
        // present (Apple's selectable mode). The selected row is the element value.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val actionID = props?.stringProperty("actionID")
        val selectable = actionID != null
        @Suppress("UNCHECKED_CAST")
        val selection: List<String> = (viewModel?.value as? List<String>) ?: emptyList()
        val onSelect: (Int, List<String>) -> Unit = { index, row ->
            if (selection != row) {
                viewModel?.value = row
                actionID?.let {
                    ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = index, context = row)
                }
            }
        }

        // Hoisted so an enclosing ScrollViewReader can drive scroll-to-row.
        // Only children mode is addressable (template / homogeneous rows
        // carry no element ids); see ScrollReaderHelper.kt.
        val listState = rememberLazyListState()
        RegisterLazyScrollHandle(element, listState, vertical = true)

        // A hidden subtree must not consume touch - Apple's `.hidden()` and web's `display:none`
        // are non-interactive, but Android `hidden` is only `alpha(0f)` (invisible, still laid out
        // AND still hit-testable). In the section-switcher idiom (overlapping bodies in a ZStack,
        // all but one hidden) an invisible List on top in z-order would otherwise steal the vertical
        // drag: its LazyColumn is hit first and Compose stops hit-testing there, so the visible List
        // behind never scrolls (Missing_Features #34). A disabled `userScrollEnabled` is not enough -
        // the LazyColumn is still a hit target and still blocks the sibling. So when hidden we render
        // a bare Box that reserves the same bounded viewport size (the reserve-space semantics stay,
        // Missing_Features #30) but carries no scrollable/pointer node, so hit-testing falls through
        // to the visible sibling behind. LocalActionUIInputEnabled is provided false for a hidden
        // subtree by ProvideReactiveEnvironment (see ReactiveEnvironment.kt).
        if (!LocalActionUIInputEnabled.current) {
            Box(listModifier)
            return
        }

        // Pull-to-refresh wraps the scroll viewport when onRefreshActionID is set; otherwise
        // this renders the LazyColumn unchanged (see RefreshableScrollContainer).
        RefreshableScrollContainer(element) {
            when {
                template != null -> {
                    val rows = templateRows(element.id)
                    LazyColumn(state = listState, modifier = listModifier) {
                        itemsIndexed(rows) { index, row ->
                            SelectableRow(selectable, selected = selection == row, onClick = { onSelect(index, row) }) {
                                TemplateHelper.BuildTemplateRow(
                                    template = template, row = row, parentID = element.id, rowIndex = index,
                                )
                            }
                        }
                    }
                }

                children.isNotEmpty() -> {
                    LazyColumn(state = listState, modifier = listModifier) {
                        items(children) { child ->
                            val builder = ActionUIRegistry.lookup(child.type) ?: return@items
                            ProvideTextStyleEnvironment(child.properties, logger) {
                                builder.BuildViewWithModifiers(child, Modifier)
                            }
                        }
                    }
                }

                else -> {
                    val rows = templateRows(element.id)
                    val itemType = resolveItemType(props, logger)
                    LazyColumn(state = listState, modifier = listModifier) {
                        itemsIndexed(rows) { index, row ->
                            SelectableRow(selectable, selected = selection == row, onClick = { onSelect(index, row) }) {
                                HomogeneousRow(itemType, row.firstOrNull().orEmpty(), index, element.id)
                            }
                        }
                    }
                }
            }
        }
    }

    /** Default scroll-viewport height when JSON supplies no `frame.height`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp
}

/**
 * Wraps a data row so it can be selected. When [selectable] is false the [content]
 * renders bare (no selection affordance); otherwise it is wrapped in a
 * full-width, tappable surface that highlights when [selected]. An inner control
 * (e.g. a `Button` cell) consumes its own tap, so per-row actions and row
 * selection coexist.
 */
@Composable
private fun SelectableRow(
    selectable: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    if (!selectable) {
        content()
        return
    }
    val background = if (selected) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent
    Box(Modifier.fillMaxWidth().background(background).clickable(onClick = onClick)) {
        content()
    }
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
