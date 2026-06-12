package com.abracode.actionui.Views

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.PaneScaffoldDirective
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.intProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.coroutines.launch

/**
 * Multi-column navigation. Mirror of the Apple `NavigationSplitView` element
 * (`ActionUI/Views/NavigationSplitView.swift`), which wraps
 * `SwiftUI.NavigationSplitView`. Backed by the **native** Material3 adaptive
 * [NavigableListDetailPaneScaffold]: the same JSON renders a real multi-pane
 * layout on tablets / foldables / large windows and collapses to a single pane on
 * phones - the Android counterpart of SwiftUI's iPad-expand / iPhone-collapse
 * behavior, driven by the window size class the scaffold reads internally. No
 * `:android` fork; one canonical shape ([[android-native-first]]).
 *
 * Named containers:
 *   * `sidebar` - the list pane (required).
 *   * `content` - the optional middle pane. Its presence switches the element from
 *     two-pane (sidebar | detail) to three-pane (sidebar | content | detail),
 *     mapped onto the scaffold's `List` / `Detail` / `Extra` roles respectively.
 *   * `detail`  - the detail pane shown until a selection is made (the
 *     "Select an item" placeholder). In three-pane it occupies the `Extra` role.
 *   * `destinations` - the detail targets, each addressed by its `id`.
 *
 * The selection-driven form is the primary one: the `sidebar`'s children carry a
 * `destinationViewId` linking to a `destinations` entry; selecting a row shows that
 * destination in the deepest pane (`Detail` for two-pane, `Extra` for three-pane) -
 * no `NavigationLink` needed, exactly as on Apple. With no `destinations`, the panes
 * render statically.
 *
 * **Three-pane width.** The adaptive directive shows two panes side by side by
 * default even on expanded width; [customizeSplitDirective] raises
 * `maxHorizontalPartitions` to 3 for the three-pane form so a wide window
 * (large tablet / unfolded foldable) shows all three columns at once, paging to
 * pairs on narrower ones - matching iPad's three-column / two-column behavior.
 *
 * **State (`selectedDestination`, `columnVisibility`).** Like Apple, the selected
 * destination id is the `selectedDestination` element state (an `Int`; `0` = none)
 * and the column layout is the `columnVisibility` state (a `String`:
 * `automatic` / `all` / `doubleColumn` / `detail`, default `all`). Both are seeded
 * by [initialStates] (the latter from the author's `columnVisibility` property),
 * host-addressable, and bound to the element `ViewModel` when a window is in scope,
 * else local state - the dual-path binding the other controls use. `actionID` fires
 * on each user selection with the new id as `context`. `columnVisibility` is a
 * best-effort map of SwiftUI's `NavigationSplitViewVisibility` onto the adaptive
 * navigator (which has no literal visibility binding): writing `detail` foregrounds
 * the detail pane; the other values return to the list (both meaningful on a
 * collapsed/compact window).
 *
 * **`style`.** `prominentDetail` narrows the list column (via the directive's
 * `defaultPanePreferredWidth`) so the detail dominates; `balanced` / `automatic`
 * keep the default split - the closest native analog of
 * `.navigationSplitViewStyle`, which Material3 has no direct equivalent for.
 *
 * **Degrades vs. Apple (documented).** Sidebar rows are text-only (no SF Symbol;
 * icons are the B2 track). `columnVisibility` and `style` are approximate maps as
 * noted above rather than literal SwiftUI bindings.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
object NavigationSplitView : ActionUIViewConstruction {

    /** Element-state key holding the selected destination id (`0` = none). */
    const val SELECTED_DESTINATION_KEY = "selectedDestination"

    /** Element-state key holding the column visibility (`all` by default). */
    const val COLUMN_VISIBILITY_KEY = "columnVisibility"

    override fun initialStates(element: ActionUIElement): Map<String, Any> = mapOf(
        SELECTED_DESTINATION_KEY to 0,
        COLUMN_VISIBILITY_KEY to (element.properties?.stringProperty("columnVisibility") ?: "all"),
    )

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val sidebar = element.sidebar
        if (sidebar == null) {
            logger.log("NavigationSplitView requires a 'sidebar'; nothing rendered", LoggerLevel.warning)
            return
        }
        val content = element.content
        val detail = element.detail
        val threePane = content != null
        val destinations = remember(element) { navigationSplitDestinations(element) }

        val actionID = element.properties?.stringProperty("actionID")
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localSelection by rememberSaveable(element.id) { mutableStateOf(0) }
        val selected = if (viewModel != null) {
            (viewModel.states[SELECTED_DESTINATION_KEY] as? Int) ?: 0
        } else {
            localSelection
        }

        val visibility = resolveSplitColumnVisibility(
            (viewModel?.states?.get(COLUMN_VISIBILITY_KEY) as? String)
                ?: element.properties?.stringProperty("columnVisibility"),
        )
        val style = resolveSplitStyle(element.properties?.stringProperty("style"))

        val windowInfo = currentWindowAdaptiveInfo()
        val directive = remember(windowInfo, threePane, style) {
            customizeSplitDirective(calculatePaneScaffoldDirective(windowInfo), threePane, style)
        }
        val navigator = rememberListDetailPaneScaffoldNavigator<Any>(scaffoldDirective = directive)
        val scope = rememberCoroutineScope()

        // The pane a selection drives: the detail for two-pane, the trailing extra
        // for three-pane (where the middle pane is the static `content`).
        val deepestRole =
            if (threePane) ListDetailPaneScaffoldRole.Extra else ListDetailPaneScaffoldRole.Detail

        val onSelect: (Int) -> Unit = { destId ->
            if (destId != selected) {
                if (viewModel != null) viewModel.states[SELECTED_DESTINATION_KEY] = destId else localSelection = destId
                actionID?.let {
                    ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0, context = destId)
                }
            }
            // Surface the destination pane (a no-op when already side-by-side on a
            // wide window; switches to it on a collapsed/compact one).
            scope.launch { navigator.navigateTo(deepestRole) }
        }

        // Honor columnVisibility programmatically. SwiftUI's NavigationSplitViewVisibility
        // has no literal counterpart in the adaptive navigator, so this is a best-effort
        // map: `detail` foregrounds the detail pane; the other values return to the list.
        // Both are meaningful on a collapsed/compact window and harmless when side by side.
        LaunchedEffect(visibility, deepestRole) {
            when (visibility) {
                SplitColumnVisibility.Detail -> navigator.navigateTo(deepestRole)
                else -> if (navigator.canNavigateBack()) navigator.navigateBack()
            }
        }

        NavigableListDetailPaneScaffold(
            navigator = navigator,
            modifier = modifier,
            listPane = {
                AnimatedPane {
                    SidebarPane(sidebar, destinations, selected, logger, onSelect)
                }
            },
            detailPane = {
                AnimatedPane {
                    if (content != null) {
                        RenderPaneChild(content, Modifier.fillMaxSize(), logger)
                    } else {
                        DetailPane(selected, destinations, detail, logger)
                    }
                }
            },
            extraPane = if (threePane) {
                { AnimatedPane { DetailPane(selected, destinations, detail, logger) } }
            } else {
                null
            },
        )
    }
}

/** SwiftUI `NavigationSplitViewVisibility`, mapped to adaptive-navigator intent. */
internal enum class SplitColumnVisibility { Automatic, All, DoubleColumn, Detail }

/** Resolves the `columnVisibility` property/state; unknown or absent -> [SplitColumnVisibility.All]. */
internal fun resolveSplitColumnVisibility(value: String?): SplitColumnVisibility = when (value) {
    "automatic" -> SplitColumnVisibility.Automatic
    "doubleColumn" -> SplitColumnVisibility.DoubleColumn
    "detail" -> SplitColumnVisibility.Detail
    else -> SplitColumnVisibility.All
}

/** SwiftUI `NavigationSplitViewStyle`. */
internal enum class SplitStyle { Automatic, Balanced, ProminentDetail }

/** Resolves the `style` property; unknown or absent -> [SplitStyle.Automatic]. */
internal fun resolveSplitStyle(value: String?): SplitStyle = when (value) {
    "balanced" -> SplitStyle.Balanced
    "prominentDetail" -> SplitStyle.ProminentDetail
    else -> SplitStyle.Automatic
}

/** List-pane width for `prominentDetail`: a narrow list so the detail dominates. */
private val PROMINENT_DETAIL_LIST_WIDTH: Dp = 280.dp

/**
 * Tunes the adaptive directive for this split: three-pane raises
 * `maxHorizontalPartitions` to 3 so a wide window shows all columns at once (the
 * default caps at 2, even on expanded width); `prominentDetail` narrows the list
 * column. Returns the base directive unchanged when neither applies. Pure.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
internal fun customizeSplitDirective(
    base: PaneScaffoldDirective,
    threePane: Boolean,
    style: SplitStyle,
): PaneScaffoldDirective {
    val maxPartitions =
        if (threePane && base.maxHorizontalPartitions >= 2) 3 else base.maxHorizontalPartitions
    val listWidth =
        if (style == SplitStyle.ProminentDetail) PROMINENT_DETAIL_LIST_WIDTH else base.defaultPanePreferredWidth
    if (maxPartitions == base.maxHorizontalPartitions && listWidth == base.defaultPanePreferredWidth) {
        return base
    }
    return PaneScaffoldDirective(
        maxHorizontalPartitions = maxPartitions,
        horizontalPartitionSpacerSize = base.horizontalPartitionSpacerSize,
        maxVerticalPartitions = base.maxVerticalPartitions,
        verticalPartitionSpacerSize = base.verticalPartitionSpacerSize,
        defaultPanePreferredWidth = listWidth,
        excludedBounds = base.excludedBounds,
    )
}

/**
 * The detail targets keyed by `id`, from the `destinations` array (entries without
 * a positive `id` are skipped - the detail pane addresses by id). Pure, so it is
 * unit-testable.
 */
internal fun navigationSplitDestinations(element: ActionUIElement): Map<Int, ActionUIElement> {
    val map = LinkedHashMap<Int, ActionUIElement>()
    element.destinations?.forEach { if (it.id != 0) map[it.id] = it }
    return map
}

/**
 * The list pane. In the selection-driven form (there are `destinations` and the
 * sidebar has children) each child is rendered as a tappable row whose
 * `destinationViewId` selects the matching detail; the selected row is tinted.
 * Otherwise the `sidebar` is rendered as a static pane through the registry.
 */
@Composable
private fun SidebarPane(
    sidebar: ActionUIElement,
    destinations: Map<Int, ActionUIElement>,
    selected: Int,
    logger: ActionUILogger,
    onSelect: (Int) -> Unit,
) {
    val rows = sidebar.children.orEmpty()
    if (destinations.isEmpty() || rows.isEmpty()) {
        RenderPaneChild(sidebar, Modifier.fillMaxSize(), logger)
        return
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        rows.forEach { row ->
            val destId = row.properties?.intProperty("destinationViewId")
            var rowModifier = Modifier.fillMaxWidth()
            if (destId != null) {
                rowModifier = rowModifier.clickable { onSelect(destId) }
                if (destId == selected) {
                    rowModifier = rowModifier.background(MaterialTheme.colorScheme.secondaryContainer)
                }
            }
            rowModifier = rowModifier.padding(horizontal = 16.dp, vertical = 12.dp)
            Box(rowModifier) { RenderPaneChild(row, Modifier, logger) }
        }
    }
}

/** The detail pane: the selected destination, else the static `detail` placeholder. */
@Composable
private fun DetailPane(
    selected: Int,
    destinations: Map<Int, ActionUIElement>,
    defaultDetail: ActionUIElement?,
    logger: ActionUILogger,
) {
    val target = destinations[selected] ?: defaultDetail ?: return
    RenderPaneChild(target, Modifier.fillMaxSize(), logger)
}

/** Renders one pane child through the normal pipeline. */
@Composable
private fun RenderPaneChild(element: ActionUIElement, modifier: Modifier, logger: ActionUILogger) {
    val builder = ActionUIRegistry.lookup(element.type) ?: return
    ProvideTextStyleEnvironment(element.properties, logger) {
        builder.BuildViewWithModifiers(element, modifier)
    }
}
