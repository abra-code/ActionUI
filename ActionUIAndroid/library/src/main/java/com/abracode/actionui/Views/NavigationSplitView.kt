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
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.intProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.coroutines.launch

/**
 * Multi-column navigation. Mirror of the Apple `NavigationSplitView` element
 * (`ActionUI/Views/NavigationSplitView.swift`), which wraps
 * `SwiftUI.NavigationSplitView`. Backed by the **native** Material3 adaptive
 * [NavigableListDetailPaneScaffold]: the same JSON renders a real two-pane
 * (sidebar | detail) layout on tablets / foldables / large windows and collapses
 * to a single pane on phones - the Android counterpart of SwiftUI's iPad-expand /
 * iPhone-collapse behavior, driven by the window size class the scaffold reads
 * internally. No `:android` fork; one canonical shape ([[android-native-first]]).
 *
 * Named containers:
 *   * `sidebar` - the list pane (required).
 *   * `detail`  - the detail pane shown until a selection is made (the
 *     "Select an item" placeholder).
 *   * `destinations` - the detail targets, each addressed by its `id`.
 *
 * **Two-pane only (this slice).** The selection-driven form is the primary one:
 * the `sidebar`'s children carry a `destinationViewId` linking to a `destinations`
 * entry; selecting a row shows that destination in the detail pane (no
 * `NavigationLink` needed, exactly as on Apple). With no `destinations`, the
 * `sidebar` and `detail` render as static panes. The 3-pane `content` column is a
 * follow-up (`SupportingPaneScaffold`).
 *
 * **State (`selectedDestination`).** Like Apple, the selected destination id is the
 * `selectedDestination` element state (an `Int`; `0` = none), seeded by
 * [initialStates] and host-addressable; `actionID` fires on each user change with
 * the new id as `context`. Bound to the element `ViewModel` when a window is in
 * scope, else local state - the dual-path binding the other controls use.
 *
 * **Degrades vs. Apple (documented).** Sidebar rows are text-only (no SF Symbol;
 * icons are the B2 track). `columnVisibility` is managed by the adaptive scaffold,
 * not yet exposed as a writable state; `style` (`balanced`/`prominentDetail`) is
 * accepted but not honored. The 3-pane `content` form is deferred (2-pane only).
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
object NavigationSplitView : ActionUIViewConstruction {

    /** Element-state key holding the selected destination id (`0` = none). */
    const val SELECTED_DESTINATION_KEY = "selectedDestination"

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(SELECTED_DESTINATION_KEY to 0)

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val sidebar = element.sidebar
        if (sidebar == null) {
            logger.log("NavigationSplitView requires a 'sidebar'; nothing rendered", LoggerLevel.warning)
            return
        }
        val detail = element.detail
        val destinations = remember(element) { navigationSplitDestinations(element) }

        val actionID = element.properties?.stringProperty("actionID")
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localSelection by rememberSaveable(element.id) { mutableStateOf(0) }
        val selected = if (viewModel != null) {
            (viewModel.states[SELECTED_DESTINATION_KEY] as? Int) ?: 0
        } else {
            localSelection
        }

        val navigator = rememberListDetailPaneScaffoldNavigator<Any>()
        val scope = rememberCoroutineScope()

        val onSelect: (Int) -> Unit = { destId ->
            if (destId != selected) {
                if (viewModel != null) viewModel.states[SELECTED_DESTINATION_KEY] = destId else localSelection = destId
                actionID?.let {
                    ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0, context = destId)
                }
            }
            // Surface the detail pane (a no-op when already side-by-side on a wide
            // window; switches to it on a collapsed/compact one).
            scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
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
                    DetailPane(selected, destinations, detail, logger)
                }
            },
        )
    }
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
        builder.BuildView(element, modifier.applyCommonProperties(element.properties, logger))
    }
}
