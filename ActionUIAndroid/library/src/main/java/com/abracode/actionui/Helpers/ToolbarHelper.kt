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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
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
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Views.MenuChild
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

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
 *
 * A `persistentToolbar` on a `NavigationStack` / `NavigationSplitView` belongs to the
 * CONTAINER instead: its items stay in the bar on every screen inside it. Android has no
 * window toolbar to hoist them into and no per-view modifier to attach them with, so the
 * container publishes them through [LocalPersistentToolbarItems] and each screen merges
 * them into its own `Scaffold` - one bar per screen, never two. See
 * `Private/Design-36-Persistent-Toolbar.md` section 6.
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
 * Element types that own a navigation context rather than being a single screen. A
 * toolbar authored on one of these belongs to the CONTAINER, not to the screen it
 * happens to be declared next to. Mirrors `ToolbarHelper.navigationContainerTypes`
 * on Apple and `NAV_CONTAINER_TYPES` in the web renderer.
 */
private val NAVIGATION_CONTAINER_TYPES = setOf("NavigationStack", "NavigationSplitView")

internal fun isNavigationContainer(elementType: String): Boolean =
    elementType in NAVIGATION_CONTAINER_TYPES

/**
 * The items a navigation container must keep in the bar on every screen inside it:
 * its `persistentToolbar` array, plus its `toolbar` array as a DEPRECATED ALIAS.
 *
 * The alias exists because a container-level `toolbar` was never a screen toolbar on
 * any host: macOS applied it outside the stack, where it reached the shared window
 * toolbar and persisted, while iOS, Android and web each dropped or misplaced it -
 * Android never read it at all. Reading it here gives all four hosts one behavior and
 * keeps existing documents working unchanged. [WindowModel] logs a deprecation warning
 * naming the element when it sees one.
 *
 * Order is only meaningful against the SCREEN's own items, which are applied first so
 * the persistent ones sit at the outer edge of each slot; between these two keys it is
 * unspecified, and a document should author one or the other, never both. Pure.
 */
internal fun persistentToolbarItems(element: ActionUIElement): List<ActionUIElement> =
    element.persistentToolbar.orEmpty() + element.toolbar.orEmpty()

/**
 * The items to apply as THIS SCREEN's own toolbar.
 *
 * Empty for a navigation container: its `toolbar` belongs to the container, and its own
 * builder applies it to every screen inside instead. Without this a nested
 * `NavigationStack` used as a destination would render its persistent items once as its
 * parent screen's bar and again on each of its own screens. Pure.
 */
internal fun screenToolbarItems(element: ActionUIElement): List<ActionUIElement> =
    if (isNavigationContainer(element.type)) emptyList() else element.toolbar.orEmpty()

/**
 * The persistent items published by the enclosing navigation container(s), for the
 * screen currently being rendered inside them.
 *
 * A container cannot serve its screens by wrapping them: on Android a screen's bar is a
 * `Scaffold` the screen itself owns, and a `Scaffold` above the `NavHost` would stack a
 * second bar over any screen that declares its own. So the container PUBLISHES here and
 * each screen merges what it finds into its own bar - the same publish-not-wrap shape
 * the Apple hosts use through `inheritedPersistentToolbar`, and the reason a
 * `NavigationStack` nested in a split view's detail pane works: the inner container
 * appends to what it inherits rather than replacing it.
 *
 * Presentation boundaries (`popover`, and defensively the element modals) reset this to
 * empty: a modal is not a screen inside the container's navigation.
 */
val LocalPersistentToolbarItems: ProvidableCompositionLocal<List<ActionUIElement>> =
    compositionLocalOf { emptyList() }

/**
 * Clears the published items across a presentation boundary (`sheet` /
 * `fullScreenCover` / `popover`). A modal is not a screen inside the presenting
 * container's navigation, so it must not inherit that container's bar.
 *
 * Load-bearing at ONE of the three sites today: `PopoverHelper`'s `Popup` is composed
 * inline at the carrier, which usually sits deep inside a navigation screen, so Compose
 * would propagate the local straight into it. The two `ElementModalHost` sites are
 * defensive - `ActionUI.kt` composes that host as a sibling of the root at the window
 * level, where the local is already empty - and are wrapped anyway so the invariant does
 * not silently depend on where that host happens to be composed.
 */
@Composable
fun ClearPersistentToolbarItems(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalPersistentToolbarItems provides emptyList(), content = content)
}

/**
 * True when [element] should be wrapped in a [ToolbarHost] as a screen of its own:
 * it declares a `toolbar` or a `navigationTitle`. The multi-screen navigation
 * containers are excluded - a `NavigationStack` owns a `ToolbarHost` per navigation
 * screen, and a `NavigationSplitView` manages its own per-pane chrome - so their
 * chrome lives on the views they render, not on the container element. Pure.
 */
internal fun hasRootToolbarChrome(element: ActionUIElement): Boolean =
    !isNavigationContainer(element.type) &&
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
 * Flattens this screen's toolbar items plus any [persistentItems] published by an
 * enclosing navigation container into chrome buckets: a `ToolbarItem` contributes its
 * single `content`; a `ToolbarItemGroup` contributes each of its `children`; both at
 * the item's placement slot. Unsupported placements are dropped (warned).
 *
 * The screen's own items are read through [screenToolbarItems], so a nested navigation
 * container's `toolbar` is not mistaken for a screen toolbar, and they are bucketed
 * FIRST: within a slot the persistent items then sit at the outer edge, keeping the same
 * absolute corner as screens change. Both bars are one bar, as on Apple.
 *
 * Pure (logging aside), so it is unit-testable.
 */
internal fun resolveToolbar(
    element: ActionUIElement,
    logger: ActionUILogger,
    persistentItems: List<ActionUIElement> = emptyList(),
): ToolbarBuckets {
    val leading = mutableListOf<ActionUIElement>()
    val principal = mutableListOf<ActionUIElement>()
    val trailing = mutableListOf<ActionUIElement>()
    val overflow = mutableListOf<ActionUIElement>()
    val bottom = mutableListOf<ActionUIElement>()
    (screenToolbarItems(element) + persistentItems).forEach { item ->
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
 *
 * [persistentItems] are the enclosing navigation container's items ([LocalPersistentToolbarItems]),
 * merged into this same bar after [element]'s own - one bar per screen, never two.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolbarHost(
    element: ActionUIElement,
    logger: ActionUILogger,
    modifier: Modifier = Modifier,
    persistentItems: List<ActionUIElement> = emptyList(),
    body: @Composable (PaddingValues) -> Unit,
) {
    val buckets = remember(element, persistentItems) { resolveToolbar(element, logger, persistentItems) }
    val title = element.properties?.stringProperty("navigationTitle")

    // Nothing for the top bar to show: no title and no item that lands in it. Rendering it
    // anyway leaves a blank strip above the content, which a screen carrying only
    // `bottomBar` items always got and which persistent items would otherwise put on EVERY
    // screen inside a container.
    val hasTopBar = title != null ||
        buckets.leading.isNotEmpty() || buckets.principal.isNotEmpty() ||
        buckets.trailing.isNotEmpty() || buckets.overflow.isNotEmpty()

    Scaffold(
        modifier = modifier,
        topBar = {
            if (hasTopBar) {
                val titleSlot: @Composable () -> Unit = {
                    // A runtime-hidden principal falls back to the navigationTitle
                    // (RenderChrome would render nothing and eat the title).
                    val principal = buckets.principal.firstOrNull()
                    if (principal != null && !chromeHidden(principal)) {
                        RenderChrome(principal, logger)
                    } else {
                        M3Text(title ?: "")
                    }
                }
                val navSlot: @Composable () -> Unit = {
                    Row { buckets.leading.forEach { RenderChrome(it, logger) } }
                }
                val actionsSlot: @Composable RowScope.() -> Unit = {
                    buckets.trailing.forEach { RenderChrome(it, logger) }
                    // Overflow items bypass RenderChrome (MenuChild), so the live
                    // hidden filter applies here; an all-hidden overflow drops the
                    // three-dot trigger entirely.
                    val visibleOverflow = buckets.overflow.filter { !chromeHidden(it) }
                    if (visibleOverflow.isNotEmpty()) OverflowMenu(visibleOverflow, logger)
                }
                when (resolveToolbarTitleSize(element.properties?.stringProperty("toolbarTitleDisplayMode"))) {
                    ToolbarTitleSize.Large ->
                        LargeTopAppBar(title = titleSlot, navigationIcon = navSlot, actions = actionsSlot)
                    ToolbarTitleSize.Medium ->
                        MediumTopAppBar(title = titleSlot, navigationIcon = navSlot, actions = actionsSlot)
                    ToolbarTitleSize.Small ->
                        TopAppBar(title = titleSlot, navigationIcon = navSlot, actions = actionsSlot)
                }
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
 * A Button's icon resolves through the shared `SymbolIcon` helper exactly as on a
 * standalone `Button` ([selectLabelIcon] -> [LabelIcon]): `systemImage` (SF
 * Symbol -> closest Material glyph) or `materialName:android`. Icon without a
 * `title` renders as a Material [IconButton] - the app-bar action idiom, what
 * SwiftUI's chrome does with an image-only toolbar button. Icon plus `title`
 * renders both in the [TextButton]; the glyph inherits the button's content
 * color and label style, so it matches the text automatically.
 */
// The LIVE `hidden` for a chrome element: the host's setElementProperty override
// when present, else the authored value. Reading the ViewModel's
// propertyOverrides (a SnapshotStateMap) inside composition subscribes it, so a
// runtime hidden write recomposes the chrome.
@Composable
private fun chromeHidden(element: ActionUIElement): Boolean {
    val authored = element.properties?.booleanProperty("hidden") == true
    if (element.id <= 0) return authored
    val viewModel = LocalWindowModel.current?.viewModels?.get(element.id) ?: return authored
    val override = viewModel.propertyOverrides["hidden"]
    return (override as? JsonPrimitive)?.booleanOrNull ?: authored
}

@Composable
private fun RenderChrome(element: ActionUIElement, logger: ActionUILogger) {
    // Runtime `hidden` removes a chrome action ENTIRELY (the role-gating
    // contract: controls are absent, not disabled or blank space). The Button
    // branch below reads authored properties statically and the registry
    // fallback only alpha-fades, so the live effective value is resolved here.
    if (chromeHidden(element)) return
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
