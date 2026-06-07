package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Helpers.LabelIcon
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.intProperty
import com.abracode.actionui.Helpers.selectLabelIcon
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject

/**
 * Tabbed container. Mirror of the Apple `TabView` element
 * (`ActionUI/Views/TabView.swift`), which wraps `SwiftUI.TabView`. Backed by a
 * Material3 [NavigationBar] - the native Android analog of the iOS tab bar:
 * the selected tab's `content` fills the area above a bottom bar of
 * [NavigationBarItem]s, one per `Tab` child.
 *
 * Value bridge: [ActionUIValueType.INT] - the selected tab index (0-based), so a
 * host reads it with `ActionUIModel.getElementValue` and writes it to switch tabs
 * (the bar follows). `selection` seeds the initial index (default 0); `actionID`
 * fires on every user change with the new index as `context` (parity with Apple,
 * which fires only on interaction). Bound to the element `ViewModel` when a window
 * is in scope, else local state - the dual-path binding the other controls use.
 *
 * Like a `LazyColumn`/`NavHost`, the bar needs a bounded height to sit at the
 * bottom (a `weight` content area over it); an inherited `frame.height` wins, else
 * [DEFAULT_TAB_EXTENT] keeps an unbounded parent from breaking the `weight`.
 *
 * **Tab icons.** A Tab's `systemImage` (SF Symbol) / `materialName:android` is drawn
 * in the item icon slot via the shared `SymbolIcon` seam ([LabelIcon]), sized for a
 * nav-bar item and tinted by selection. `assetImage` (asset catalog) and `badge`
 * stay deferred (the same `res/drawable` contract `Image`'s `assetName` waits on).
 * The `style` property (`page`, `sidebarAdaptable`, ...) is accepted but not
 * honored; the NavigationBar is always used.
 */
object TabView : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.INT

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.intProperty("selection") ?: 0

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = element.properties
        val tabs = element.children.orEmpty()
        if (tabs.isEmpty()) return

        val actionID = props?.stringProperty("actionID")
        val initial = (initialValue(element) as? Int) ?: 0

        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localSelection by rememberSaveable(element.id) { mutableStateOf(initial) }
        val rawSelection = if (viewModel != null) (viewModel.value as? Int) ?: initial else localSelection
        val selected = rawSelection.coerceIn(0, tabs.size - 1)

        val onSelect: (Int) -> Unit = { index ->
            if (index != selected) {
                if (viewModel != null) viewModel.value = index else localSelection = index
                actionID?.let {
                    ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0, context = index)
                }
            }
        }

        // Bounded height so the bottom bar can sit under a weighted content area.
        val hasExplicitHeight = (props?.get("frame") as? JsonObject)?.get("height") != null
        val tabModifier = if (hasExplicitHeight) modifier else modifier.height(DEFAULT_TAB_EXTENT)

        Column(modifier = tabModifier) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                RenderTabContent(tabs[selected].content, logger)
            }
            NavigationBar {
                tabs.forEachIndexed { index, tab ->
                    // The tab's SF Symbol / Material glyph, sized for a nav-bar item;
                    // NavigationBarItem tints it by selection via LocalContentColor.
                    val tabIcon = remember(tab) { selectLabelIcon(tab.properties, "assetImage", "Tab", logger) }
                    val tabImageScale = tab.properties?.stringProperty("imageScale")
                    NavigationBarItem(
                        selected = index == selected,
                        onClick = { onSelect(index) },
                        icon = {
                            LabelIcon(
                                source = tabIcon,
                                imageScale = tabImageScale,
                                contentDescription = tab.properties?.stringProperty("accessibilityLabel"),
                                elementName = "Tab",
                                defaultSizeSp = NAV_ICON_SIZE_SP,
                                logger = logger,
                            )
                        },
                        label = { M3Text(tabTitle(tab)) },
                        alwaysShowLabel = true,
                    )
                }
            }
        }
    }

    /** Content-area height when JSON supplies no `frame.height`. */
    private val DEFAULT_TAB_EXTENT = 360.dp

    /** Nav-bar item icon size (sp); a tab glyph is fixed, not font-relative. */
    private const val NAV_ICON_SIZE_SP = 24f
}

/** Renders a tab's `content` through the normal pipeline (or nothing if absent). */
@Composable
private fun RenderTabContent(content: ActionUIElement?, logger: ActionUILogger) {
    if (content == null) return
    val builder = ActionUIRegistry.lookup(content.type) ?: return
    ProvideTextStyleEnvironment(content.properties, logger) {
        builder.BuildView(content, Modifier.applyCommonProperties(content.properties, logger))
    }
}
