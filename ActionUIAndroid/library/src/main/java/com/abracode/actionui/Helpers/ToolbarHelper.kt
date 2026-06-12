package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MediumTopAppBar
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
import com.abracode.actionui.Common.LocalActionUIImageRegistry
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Views.MenuChild

/**
 * Renders an element's `toolbar` as the native Android screen chrome
 * (`Scaffold` + `TopAppBar` / `BottomAppBar`). The Android counterpart of Apple's
 * `.toolbar {}` modifier; see `Private/Android_Toolbar_Design.md`.
 *
 * SwiftUI's `.toolbar` attaches to a view and the navigation chrome renders it.
 * Android has no per-view toolbar modifier - the native home is a screen-level
 * `Scaffold` - so a `toolbar` is consumed by a screen-level host: a
 * `NavigationStack` screen (`RenderNavChild`), or the document root itself when a
 * top-level `VStack` / `List` / etc. carries a `toolbar` (`ActionUI.Render`).
 */

/** Where a toolbar item lands in the Android Scaffold chrome. */
internal enum class ToolbarSlot { Leading, Principal, Trailing, Overflow, Bottom, Unsupported }

/**
 * Maps a SwiftUI toolbar placement to an Android [ToolbarSlot]. iOS placements map
 * to the TopAppBar slots / BottomAppBar; `secondaryAction` becomes an overflow
 * menu; `keyboard` and the macOS-only placements (`navigation`/`status`) are
 * unsupported. Unknown values fall back to trailing (Apple's `automatic`). Pure.
 */
/**
 * True when [element] should be wrapped in a [ToolbarHost] as a screen of its own:
 * it declares a `toolbar` or a `navigationTitle`. The multi-screen navigation
 * containers are excluded - a `NavigationStack` owns a `ToolbarHost` per navigation
 * screen, and a `NavigationSplitView` manages its own per-pane chrome - so their
 * chrome lives on the views they render, not on the container element. Pure.
 */
internal fun hasRootToolbarChrome(element: ActionUIElement): Boolean =
    element.type != "NavigationStack" && element.type != "NavigationSplitView" &&
        (element.toolbar != null || element.properties?.stringProperty("navigationTitle") != null)

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

/** Which Material3 top-bar size renders a SwiftUI `toolbarTitleDisplayMode`. */
internal enum class ToolbarTitleSize { Small, Medium, Large }

/**
 * Maps SwiftUI's `toolbarTitleDisplayMode` to a Material3 top-bar size: `large` ->
 * `LargeTopAppBar`, `inlineLarge` -> `MediumTopAppBar` (the "between" size), and
 * `inline` / `automatic` / null / unknown -> the small `TopAppBar`. Pure.
 *
 * `automatic` maps to small for a predictable, context-free result: iOS resolves it
 * to a large title at a navigation root, which we can't infer here, so a large title
 * must be requested explicitly with `large`.
 */
internal fun resolveToolbarTitleSize(displayMode: String?): ToolbarTitleSize = when (displayMode) {
    "large" -> ToolbarTitleSize.Large
    "inlineLarge" -> ToolbarTitleSize.Medium
    else -> ToolbarTitleSize.Small
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
 * Wraps [body] in a `Scaffold` whose top app bar (and `BottomAppBar`, if any)
 * render [element]'s `toolbar` and `navigationTitle`. The top-bar size follows the
 * canonical `toolbarTitleDisplayMode` (see [resolveToolbarTitleSize]): `large` ->
 * `LargeTopAppBar`, `inlineLarge` -> `MediumTopAppBar`, otherwise the small
 * `TopAppBar`. [body] receives the Scaffold inset padding.
 *
 * [modifier] is applied to the `Scaffold`. A `NavigationStack` screen leaves it at
 * the default (the `NavHost` bounds it); the document root passes a height-bounding
 * modifier, since a `Scaffold` fills its parent and would otherwise have no finite
 * height under a scrolling host (see [[android-bounded-height-scroll]]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolbarHost(
    element: ActionUIElement,
    logger: ActionUILogger,
    modifier: Modifier = Modifier,
    body: @Composable (PaddingValues) -> Unit,
) {
    val buckets = remember(element) { resolveToolbar(element, logger) }
    val title = element.properties?.stringProperty("navigationTitle")

    Scaffold(
        modifier = modifier,
        topBar = {
            val titleSlot: @Composable () -> Unit = {
                val principal = buckets.principal.firstOrNull()
                if (principal != null) RenderChrome(principal, logger) else M3Text(title ?: "")
            }
            val navSlot: @Composable () -> Unit = {
                Row { buckets.leading.forEach { RenderChrome(it, logger) } }
            }
            val actionsSlot: @Composable RowScope.() -> Unit = {
                buckets.trailing.forEach { RenderChrome(it, logger) }
                if (buckets.overflow.isNotEmpty()) OverflowMenu(buckets.overflow, logger)
            }
            when (resolveToolbarTitleSize(element.properties?.stringProperty("toolbarTitleDisplayMode"))) {
                ToolbarTitleSize.Large ->
                    LargeTopAppBar(title = titleSlot, navigationIcon = navSlot, actions = actionsSlot)
                ToolbarTitleSize.Medium ->
                    MediumTopAppBar(title = titleSlot, navigationIcon = navSlot, actions = actionsSlot)
                ToolbarTitleSize.Small ->
                    TopAppBar(title = titleSlot, navigationIcon = navSlot, actions = actionsSlot)
            }
        },
        bottomBar = {
            if (buckets.bottom.isNotEmpty()) {
                BottomAppBar { buckets.bottom.forEach { RenderChrome(it, logger) } }
            }
        },
    ) { inner -> body(inner) }
}

/**
 * Renders one chrome item. A `Button` becomes a native app-bar action (toolbar
 * idiom; firing its `actionID`); other content (e.g. a `Menu`) is built through
 * the registry.
 *
 * **Why `Button` is special-cased instead of built through the registry.** The
 * registered `Button` renders a filled `M3Button` - a colored pill, which is the
 * wrong widget inside an app bar, where actions are borderless and inherit the
 * bar's colors. SwiftUI restyles a toolbar `Button` the same way but invisibly,
 * through the environment's implicit button style; Compose has no equivalent
 * (`M3Button` hard-codes its container colors), so the chrome host must build a
 * different composable. Here - as in `MenuChild`, where a `Button` child becomes
 * a `DropdownMenuItem` - a `Button` is a semantic action declaration (title /
 * icon / `actionID`) whose presentation the host context owns; the registry
 * fallback is for content that renders itself the same everywhere. A deliberate
 * consequence: this branch skips `applyCommonProperties`, so layout modifiers
 * (padding / frame) on a toolbar button are ignored, consistent with SwiftUI
 * toolbar items, which largely ignore layout modifiers too.
 *
 * A Button's icon resolves through the shared `SymbolIcon` seam exactly as on a
 * standalone `Button` ([selectLabelIcon] -> [LabelIcon]): `systemImage` (SF
 * Symbol -> closest Material glyph) or `materialName:android`. Icon without a
 * `title` renders as a Material [IconButton] - the app-bar action idiom, what
 * SwiftUI's chrome does with an image-only toolbar button. Icon plus `title`
 * renders both in the [TextButton]; the glyph inherits the button's content
 * color and label style, so it matches the text automatically.
 */
@Composable
private fun RenderChrome(element: ActionUIElement, logger: ActionUILogger) {
    if (element.type == "Button") {
        val props = element.properties
        val title = props?.stringProperty("title").orEmpty()
        val actionID = props?.stringProperty("actionID")
        val imageScale = props?.stringProperty("imageScale")
        val contentDescription = props?.stringProperty("accessibilityLabel")
        val imageRegistry = LocalActionUIImageRegistry.current
        val iconSource = remember(props, imageRegistry) { selectLabelIcon(props, "assetImage", "ToolbarItem", logger, imageRegistry) }
        val onClick = {
            actionID?.let { ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0) }
            Unit
        }
        if (iconSource != null && title.isEmpty()) {
            IconButton(onClick = onClick) {
                LabelIcon(
                    source = iconSource,
                    imageScale = imageScale,
                    contentDescription = contentDescription,
                    elementName = "ToolbarItem",
                    logger = logger,
                )
            }
        } else {
            TextButton(onClick = onClick) {
                val iconDrawn = LabelIcon(
                    source = iconSource,
                    imageScale = imageScale,
                    contentDescription = contentDescription,
                    elementName = "ToolbarItem",
                    logger = logger,
                )
                if (iconDrawn && title.isNotEmpty()) {
                    Spacer(Modifier.size(ButtonDefaults.IconSpacing))
                }
                M3Text(title)
            }
        }
    } else {
        val builder = ActionUIRegistry.lookup(element.type) ?: return
        ProvideTextStyleEnvironment(element.properties, logger) {
            builder.BuildViewWithModifiers(element, Modifier)
        }
    }
}

/**
 * The `secondaryAction` overflow: the standard Android three-dot (`more_vert`)
 * trigger opening a [DropdownMenu] of the items (reuses `MenuChild`). Falls back
 * to a "More" text button if the glyph is missing from the bundled font.
 */
@Composable
private fun OverflowMenu(items: List<ActionUIElement>, logger: ActionUILogger) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { expanded = true }) {
            val drawn = MaterialNameIcon(
                name = "more_vert",
                weight = MATERIAL_WEIGHT_DEFAULT,
                fill = MATERIAL_FILL_DEFAULT,
                grade = MATERIAL_GRADE_DEFAULT,
                explicitSizeSp = null,
                imageScale = null,
                contentDescription = "More",
                logger = logger,
            )
            if (!drawn) M3Text("More")
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            items.forEach { MenuChild(it, logger) { expanded = false } }
        }
    }
}
