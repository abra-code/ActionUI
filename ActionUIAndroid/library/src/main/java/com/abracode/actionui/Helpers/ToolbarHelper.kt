package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text as M3Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Views.MenuChild

/**
 * Renders an element's `toolbar` as the native Android screen chrome
 * (`Scaffold` + `TopAppBar` / `BottomAppBar`). The Android counterpart of Apple's
 * `.toolbar {}` modifier; see `Private/Android_Toolbar_Design.md`.
 *
 * SwiftUI's `.toolbar` attaches to a view and the navigation chrome renders it.
 * Android has no per-view toolbar modifier - the native home is a screen-level
 * `Scaffold` - so a `toolbar` is consumed by the navigation screen (this slice:
 * `NavigationStack`'s `RenderNavChild`), not applied as a `Modifier`.
 */

/** Where a toolbar item lands in the Android Scaffold chrome. */
internal enum class ToolbarSlot { Leading, Principal, Trailing, Overflow, Bottom, Unsupported }

/**
 * Maps a SwiftUI toolbar placement to an Android [ToolbarSlot]. iOS placements map
 * to the TopAppBar slots / BottomAppBar; `secondaryAction` becomes an overflow
 * menu; `keyboard` and the macOS-only placements (`navigation`/`status`) are
 * unsupported. Unknown values fall back to trailing (Apple's `automatic`). Pure.
 */
internal fun resolveToolbarSlot(placement: String?): ToolbarSlot = when (placement) {
    null, "automatic", "topBarTrailing", "confirmationAction",
    "destructiveAction", "primaryAction" -> ToolbarSlot.Trailing
    "topBarLeading", "cancellationAction" -> ToolbarSlot.Leading
    "principal" -> ToolbarSlot.Principal
    "secondaryAction" -> ToolbarSlot.Overflow
    "bottomBar" -> ToolbarSlot.Bottom
    "keyboard", "navigation", "status" -> ToolbarSlot.Unsupported
    else -> ToolbarSlot.Trailing
}

/** The toolbar items grouped by where they render. */
internal data class ToolbarBuckets(
    val leading: List<ActionUIElement> = emptyList(),
    val principal: List<ActionUIElement> = emptyList(),
    val trailing: List<ActionUIElement> = emptyList(),
    val overflow: List<ActionUIElement> = emptyList(),
    val bottom: List<ActionUIElement> = emptyList(),
)

/**
 * Flattens an element's `toolbar` array into chrome buckets: a `ToolbarItem`
 * contributes its single `content`; a `ToolbarItemGroup` contributes each of its
 * `children`; both at the item's placement slot. Unsupported placements are
 * dropped (warned). Pure (logging aside), so it is unit-testable.
 */
internal fun resolveToolbar(element: ActionUIElement, logger: ActionUILogger): ToolbarBuckets {
    val leading = mutableListOf<ActionUIElement>()
    val principal = mutableListOf<ActionUIElement>()
    val trailing = mutableListOf<ActionUIElement>()
    val overflow = mutableListOf<ActionUIElement>()
    val bottom = mutableListOf<ActionUIElement>()
    element.toolbar.orEmpty().forEach { item ->
        val placement = item.properties?.stringProperty("placement")
        val contents = if (item.type == "ToolbarItemGroup") item.children.orEmpty() else listOfNotNull(item.content)
        when (resolveToolbarSlot(placement)) {
            ToolbarSlot.Leading -> leading += contents
            ToolbarSlot.Principal -> principal += contents
            ToolbarSlot.Trailing -> trailing += contents
            ToolbarSlot.Overflow -> overflow += contents
            ToolbarSlot.Bottom -> bottom += contents
            ToolbarSlot.Unsupported ->
                logger.log("Toolbar placement '$placement' is not supported on Android; item dropped", LoggerLevel.warning)
        }
    }
    return ToolbarBuckets(leading, principal, trailing, overflow, bottom)
}

/**
 * Wraps [body] in a `Scaffold` whose `TopAppBar` (and `BottomAppBar`, if any)
 * render [element]'s `toolbar` and `navigationTitle`. This slice uses the small
 * `TopAppBar`; `LargeTopAppBar` (for `toolbarTitleDisplayMode: large`) is a
 * follow-up. [body] receives the Scaffold inset padding.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolbarHost(element: ActionUIElement, logger: ActionUILogger, body: @Composable (PaddingValues) -> Unit) {
    val buckets = remember(element) { resolveToolbar(element, logger) }
    val title = element.properties?.stringProperty("navigationTitle")

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    val principal = buckets.principal.firstOrNull()
                    if (principal != null) RenderChrome(principal, logger) else M3Text(title ?: "")
                },
                navigationIcon = {
                    Row { buckets.leading.forEach { RenderChrome(it, logger) } }
                },
                actions = {
                    buckets.trailing.forEach { RenderChrome(it, logger) }
                    if (buckets.overflow.isNotEmpty()) OverflowMenu(buckets.overflow, logger)
                },
            )
        },
        bottomBar = {
            if (buckets.bottom.isNotEmpty()) {
                BottomAppBar { buckets.bottom.forEach { RenderChrome(it, logger) } }
            }
        },
    ) { inner -> body(inner) }
}

/**
 * Renders one chrome item. A `Button` becomes a compact [TextButton] (toolbar
 * idiom; firing its `actionID`); other content (e.g. a `Menu`) is built through
 * the registry. Toolbar buttons are text-only (no SF Symbol; icons are B2).
 */
@Composable
private fun RenderChrome(element: ActionUIElement, logger: ActionUILogger) {
    if (element.type == "Button") {
        val title = element.properties?.stringProperty("title").orEmpty()
        val actionID = element.properties?.stringProperty("actionID")
        TextButton(onClick = {
            actionID?.let { ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0) }
        }) { M3Text(title) }
    } else {
        val builder = ActionUIRegistry.lookup(element.type) ?: return
        ProvideTextStyleEnvironment(element.properties, logger) {
            builder.BuildView(element, Modifier.applyCommonProperties(element.properties, logger))
        }
    }
}

/** The `secondaryAction` overflow: a "More" trigger opening a [DropdownMenu] of the items (reuses `MenuChild`). */
@Composable
private fun OverflowMenu(items: List<ActionUIElement>, logger: ActionUILogger) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        TextButton(onClick = { expanded = true }) { M3Text("More") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            items.forEach { MenuChild(it, logger) { expanded = false } }
        }
    }
}
