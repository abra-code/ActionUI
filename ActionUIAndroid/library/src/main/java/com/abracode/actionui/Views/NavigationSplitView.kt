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
import androidx.compose.material3.LocalContentColor
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
import androidx.compose.runtime.CompositionLocalProvider
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
import com.abracode.actionui.Helpers.LocalPersistentToolbarItems
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.ToolbarHost
import com.abracode.actionui.Helpers.intProperty
import com.abracode.actionui.Helpers.isNavigationContainer
import com.abracode.actionui.Helpers.persistentToolbarItems
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
 * **Sidebar rows + icons.** Each row renders through the full element pipeline
 * ([RenderPaneChild]), so an Apple-canonical `Label` row carries its leading icon
 * for free: `systemImage` resolves through the bundled SF->Material map (no host
 * registry needed), exactly as on the `Image` / `Label` elements elsewhere. The
 * selected row tints both its background (`secondaryContainer`) and its content
 * (`onSecondaryContainer`, provided through [LocalContentColor] so a Label's icon
 * and title follow) - the Material analog of SwiftUI's sidebar selection emphasis.
 *
 * **Per-pane chrome.** Each pane (the sidebar, the `content` middle pane, and the
 * detail / its switched destination) carries its own navigation chrome: a pane
 * whose root element declares a `toolbar` or `navigationTitle` is wrapped in a
 * per-pane [ToolbarHost] (`Scaffold` + `TopAppBar`), so the sidebar and the detail
 * get separate top bars rather than one shared bar - the Android analog of
 * SwiftUI, where each column has its own toolbar. This is [hasRootToolbarChrome]'s
 * reason for excluding `NavigationSplitView` from root chrome: the chrome lives on
 * the panes, applied here, exactly as `NavigationStack` applies it per screen.
 *
 * **Degrades vs. Apple (documented).** `columnVisibility` and `style` are
 * approximate maps as noted above rather than literal SwiftUI bindings.
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

        // This split view's persistent items, appended to whatever an enclosing container
        // already published (see LocalPersistentToolbarItems).
        val inheritedPersistent = LocalPersistentToolbarItems.current
        val persistent = remember(element, inheritedPersistent) {
            inheritedPersistent + persistentToolbarItems(element)
        }

        // Which panes carry them - see [splitPanePersistence] for the rule.
        val collapsed = directive.maxHorizontalPartitions <= 1
        // A selection-driven split with no `detail` fallback shows NOTHING in its deepest
        // pane until the first selection. Wide, that pane is on screen and empty, so items
        // parked there would be invisible; the list pane has to hold them until a
        // destination exists to hold them instead.
        val deepestPaneIsEmpty = destinations[selected] == null && detail == null
        val carriers = splitPanePersistence(collapsed, threePane, deepestPaneIsEmpty)
        val listPanePersistent = if (carriers.list) persistent else emptyList()
        val detailPanePersistent = if (carriers.detail) persistent else emptyList()
        val extraPanePersistent = if (carriers.extra) persistent else emptyList()

        NavigableListDetailPaneScaffold(
            navigator = navigator,
            modifier = modifier,
            listPane = {
                AnimatedPane {
                    CompositionLocalProvider(LocalPersistentToolbarItems provides listPanePersistent) {
                        SidebarPane(sidebar, destinations, selected, logger, onSelect)
                    }
                }
            },
            detailPane = {
                AnimatedPane {
                    CompositionLocalProvider(LocalPersistentToolbarItems provides detailPanePersistent) {
                        if (content != null) {
                            RenderPane(content, logger)
                        } else {
                            DetailPane(selected, destinations, detail, logger)
                        }
                    }
                }
            },
            extraPane = if (threePane) {
                {
                    AnimatedPane {
                        CompositionLocalProvider(LocalPersistentToolbarItems provides extraPanePersistent) {
                            DetailPane(selected, destinations, detail, logger)
                        }
                    }
                }
            } else {
                null
            },
        )
    }
}

/** Which of a split view's panes carry the container's persistent toolbar items. */
internal data class SplitPanePersistence(val list: Boolean, val detail: Boolean, val extra: Boolean)

/**
 * Decides which panes carry the persistent items, given whether the window is too narrow
 * to show two panes at once ([collapsed]), whether there is a middle `content` pane
 * ([threePane]), and whether the deepest pane currently has nothing to render
 * ([deepestPaneIsEmpty]).
 *
 * Every pane renders its OWN bar, so handing the items to all of them would show one
 * authored item once per visible column. Two rules resolve that:
 *
 *  - Collapsed, exactly one pane is on screen at a time and it can be any of them, so all
 *    panes carry the items and only the visible one is ever seen.
 *  - Expanded, only the DEEPEST pane carries them - the one a selection drives, so they
 *    keep the same place as the user navigates. This is the same rule iOS applies by
 *    withdrawing the items from the leading column in regular width.
 *
 * The exception is [deepestPaneIsEmpty]: a selection-driven split with no `detail`
 * fallback renders nothing at all in its deepest pane until the first selection, so items
 * parked there would be on screen and invisible. The list pane holds them until there is
 * a destination to hold them instead. Pure, so it is unit-testable - the alternative is a
 * rule that can only be checked by looking at a tablet.
 */
internal fun splitPanePersistence(
    collapsed: Boolean,
    threePane: Boolean,
    deepestPaneIsEmpty: Boolean,
): SplitPanePersistence {
    if (collapsed) return SplitPanePersistence(list = true, detail = true, extra = true)
    if (deepestPaneIsEmpty) return SplitPanePersistence(list = true, detail = false, extra = false)
    // Deepest is the extra pane when there is a middle content pane, else the detail.
    return SplitPanePersistence(list = false, detail = !threePane, extra = threePane)
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
 * sidebar has children) each child is rendered through the full element pipeline
 * as a tappable row whose `destinationViewId` selects the matching detail; an
 * Apple-canonical `Label` row therefore shows its `systemImage` leading icon for
 * free. The selected row tints its background (`secondaryContainer`) and its
 * content (`onSecondaryContainer`). Otherwise the `sidebar` is rendered as a
 * static pane through the registry.
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
        // Static sidebar: render the whole element as a pane (its own chrome included).
        RenderPane(sidebar, logger)
        return
    }
    // Selection-driven sidebar: the List element *is* the pane, so its own
    // `toolbar` / `navigationTitle` wraps the row column, and each child is a row.
    PaneChrome(sidebar, logger) { paneModifier ->
        Column(paneModifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            rows.forEach { row ->
                val destId = row.properties?.intProperty("destinationViewId")
                val isSelected = isSidebarRowSelected(destId, selected)
                var rowModifier = Modifier.fillMaxWidth()
                if (destId != null) {
                    rowModifier = rowModifier.clickable { onSelect(destId) }
                }
                if (isSelected) {
                    rowModifier = rowModifier.background(MaterialTheme.colorScheme.secondaryContainer)
                }
                rowModifier = rowModifier.padding(horizontal = 16.dp, vertical = 12.dp)
                Box(rowModifier) {
                    if (isSelected) {
                        // Pair the tinted background with its Material "on" content color so a
                        // Label row's icon + title stay legible and read as selected - the
                        // analog of SwiftUI's sidebar selection emphasis. An explicit row
                        // `foregroundStyle` still wins (it is applied inside RenderPaneChild).
                        CompositionLocalProvider(
                            LocalContentColor provides MaterialTheme.colorScheme.onSecondaryContainer,
                        ) {
                            RenderPaneChild(row, Modifier, logger)
                        }
                    } else {
                        RenderPaneChild(row, Modifier, logger)
                    }
                }
            }
        }
    }
}

/**
 * Whether a sidebar row is the selected one: it must link to a destination
 * ([destId] non-null) and that destination must be the current [selected]. A row
 * without a `destinationViewId` (a static header / spacer) is never highlighted.
 * Pure, so it is unit-testable.
 */
internal fun isSidebarRowSelected(destId: Int?, selected: Int): Boolean =
    destId != null && destId == selected

/** The detail pane: the selected destination, else the static `detail` placeholder. */
@Composable
private fun DetailPane(
    selected: Int,
    destinations: Map<Int, ActionUIElement>,
    defaultDetail: ActionUIElement?,
    logger: ActionUILogger,
) {
    val target = destinations[selected] ?: defaultDetail ?: return
    RenderPane(target, logger)
}

/**
 * A pane carries its own navigation chrome when its root element declares a
 * `toolbar` or a `navigationTitle` - the same test [hasRootToolbarChrome] applies
 * at the document root and `NavigationStack` applies per screen. Pure, so it is
 * unit-testable.
 */
internal fun paneHasChrome(element: ActionUIElement): Boolean =
    element.toolbar != null || element.properties?.stringProperty("navigationTitle") != null

/**
 * Wraps a pane's [content] in a per-pane [ToolbarHost] (`Scaffold` + `TopAppBar` /
 * `BottomAppBar`) when [element] declares chrome ([paneHasChrome]), handing the
 * scaffold inset to [content]; otherwise invokes [content] with a plain [Modifier]
 * and no chrome. The split-view analog of SwiftUI's per-column toolbars; the
 * sidebar pane and the detail pane each get their own bar this way.
 */
@Composable
private fun PaneChrome(
    element: ActionUIElement,
    logger: ActionUILogger,
    content: @Composable (Modifier) -> Unit,
) {
    // A pane that is itself a navigation container renders its own screens and merges the
    // published items into each of their bars; a bar here would sit above its NavHost and
    // stack a second one over every screen inside. This is the split fixture's own shape - a
    // NavigationStack in the detail pane - and SharedCare's wide shell.
    if (isNavigationContainer(element.type)) {
        content(Modifier)
        return
    }
    val persistent = LocalPersistentToolbarItems.current
    if (paneHasChrome(element) || persistent.isNotEmpty()) {
        ToolbarHost(element, logger, persistentItems = persistent) { inner ->
            content(Modifier.padding(inner))
        }
    } else {
        content(Modifier)
    }
}

/**
 * Renders one pane (sidebar / content / detail / destination) filling its column,
 * inside its per-pane chrome when it declares any ([PaneChrome]).
 */
@Composable
private fun RenderPane(element: ActionUIElement, logger: ActionUILogger) {
    PaneChrome(element, logger) { paneModifier ->
        RenderPaneChild(element, paneModifier.fillMaxSize(), logger)
    }
}

/** Renders one pane child (or sidebar row) through the normal pipeline, bare. */
@Composable
private fun RenderPaneChild(element: ActionUIElement, modifier: Modifier, logger: ActionUILogger) {
    val builder = ActionUIRegistry.lookup(element.type) ?: return
    ProvideTextStyleEnvironment(element.properties, logger) {
        builder.BuildViewWithModifiers(element, modifier)
    }
}
