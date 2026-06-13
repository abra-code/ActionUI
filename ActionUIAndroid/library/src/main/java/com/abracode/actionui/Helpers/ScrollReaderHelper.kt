package com.abracode.actionui.Helpers

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlin.math.roundToInt

/**
 * The scroll-to machinery behind the `ScrollViewReader` element
 * (`Views/ScrollViewReader.kt`) - the Android counterpart of SwiftUI's
 * `ScrollViewProxy.scrollTo(_:anchor:)`. SwiftUI hands the reader's closure a
 * proxy that can address any `.id()`-tagged view inside any scrollable in the
 * subtree; Compose has no ambient equivalent, so the reader provides a
 * [ScrollViewReaderState] through [LocalScrollViewReaderState] and the
 * scrollables in its subtree enroll themselves:
 *
 *   * **Plain path** (`ScrollView`): the container registers a
 *     [PlainScrollHandle] (its `ScrollState`s plus its viewport coordinates,
 *     via [rememberPlainScrollRegistration]), and every element with a
 *     positive id registers its own [LayoutCoordinates] at the shared build
 *     entry point (`BuildViewWithModifiers` -> [scrollTargetModifier]). All
 *     content in a plain scroll container is composed, so any target is
 *     addressable exactly: the handle converts the target's position into a
 *     content offset and animates its `ScrollState` there.
 *   * **Lazy path** (`LazyVStack` / `LazyHStack` / `List` children mode): an
 *     off-screen row is not composed and has no coordinates, so the container
 *     registers a [LazyScrollHandle] (its hoisted `LazyListState` plus an
 *     id-to-row-index resolver, via [RegisterLazyScrollHandle]). The resolver
 *     scans the authored `children` for the row whose subtree contains the
 *     target id ([lazyChildIndexOf]) - the row is the scroll unit, exactly
 *     SwiftUI's behavior for an id inside a lazy row. Template and
 *     homogeneous rows carry no element ids and are not addressable
 *     (documented divergence; the lazy grids are also not enrolled yet).
 *
 * Dispatch ([ScrollViewReaderState.scrollTo]) tries the lazy handles first -
 * they can reach uncomposed rows and a visible lazy row would otherwise be
 * mis-routed to an enclosing plain container - then the registered target
 * coordinates. Targets and handles come and go with composition
 * (`DisposableEffect`), so a disposed lazy row or dismissed screen never
 * leaves a stale entry. Everything here runs on the main thread (registration
 * during composition/layout, dispatch from the reader's `LaunchedEffect`), so
 * the registries are plain collections, not snapshot state.
 *
 * **Anchor semantics.** SwiftUI's anchor vocabulary here is `top` / `center` /
 * `bottom` (the Apple validator's set). As `UnitPoint`s all three sit at
 * x = 0.5, so the cross axis - and any horizontal scrolling - always centers;
 * only the vertical placement varies ([anchorOffset]).
 */
val LocalScrollViewReaderState: ProvidableCompositionLocal<ScrollViewReaderState?> =
    compositionLocalOf { null }

/** How many frames the dispatcher waits for targets/handles to register. */
private const val MAX_RESOLVE_FRAMES = 8

/** Where the scrolled-to element lands in the viewport (SwiftUI `UnitPoint` vocabulary). */
internal enum class ScrollAnchor { Top, Center, Bottom }

/**
 * The registry one `ScrollViewReader` provides to its subtree. See the file
 * header for the two enrollment paths and the dispatch order.
 */
class ScrollViewReaderState internal constructor() {
    internal val targetCoordinates = mutableMapOf<Int, LayoutCoordinates>()
    private val plainHandles = mutableListOf<PlainScrollHandle>()
    private val lazyHandles = mutableListOf<LazyScrollHandle>()

    internal fun registerPlainHandle(handle: PlainScrollHandle) { plainHandles.add(handle) }
    internal fun unregisterPlainHandle(handle: PlainScrollHandle) { plainHandles.remove(handle) }
    internal fun registerLazyHandle(handle: LazyScrollHandle) { lazyHandles.add(handle) }
    internal fun unregisterLazyHandle(handle: LazyScrollHandle) { lazyHandles.remove(handle) }

    /**
     * Scrolls the enrolled scrollable that owns [id] so the element lands at
     * [anchor]. Registration happens during composition and layout while this
     * runs from the reader's `LaunchedEffect`, so an unresolvable id is
     * retried for a few frames (covers the authored-`scrollTo` first
     * composition, where layout has not happened yet) before warning.
     */
    internal suspend fun scrollTo(id: Int, anchor: ScrollAnchor, logger: ActionUILogger? = null) {
        repeat(MAX_RESOLVE_FRAMES) {
            if (tryScrollTo(id, anchor)) return
            withFrameNanos { }
        }
        logger?.log(
            "ScrollViewReader: no scrollable element with id $id under this reader; ignoring scrollTo",
            LoggerLevel.warning,
        )
    }

    private suspend fun tryScrollTo(id: Int, anchor: ScrollAnchor): Boolean {
        // Lazy first: only a LazyListState can reach an uncomposed row, and a
        // visible lazy row must scroll its own list, not an outer ScrollView.
        for (handle in lazyHandles.toList()) {
            val index = handle.indexOf(id) ?: continue
            handle.scrollToIndex(index, anchor)
            return true
        }
        val target = targetCoordinates[id]?.takeIf { it.isAttached } ?: return false
        val handle = plainHandles.firstOrNull { it.isAncestorOf(target) }
            ?: plainHandles.singleOrNull()
            ?: return false
        handle.scrollTo(target, anchor)
        return true
    }
}

/**
 * A plain scroll container (`ScrollView`): its `ScrollState`s (per enrolled
 * axis) and viewport coordinates. The target's offset inside the content is
 * `viewport position + current scroll value`; the anchor adjustment then
 * decides where in the viewport it lands.
 */
internal class PlainScrollHandle(
    private val verticalState: ScrollState?,
    private val horizontalState: ScrollState?,
) {
    var coordinates: LayoutCoordinates? = null

    /** Whether [target] sits inside this container's layout subtree. */
    fun isAncestorOf(target: LayoutCoordinates): Boolean {
        val container = coordinates?.takeIf { it.isAttached } ?: return false
        return generateSequence(target.parentCoordinates) { it.parentCoordinates }
            .any { it === container }
    }

    suspend fun scrollTo(target: LayoutCoordinates, anchor: ScrollAnchor) {
        val container = coordinates?.takeIf { it.isAttached } ?: return
        val position = container.localPositionOf(target, Offset.Zero)
        verticalState?.let { state ->
            val desired = state.value + position.y.roundToInt() -
                anchorOffset(anchor, container.size.height, target.size.height)
            state.animateScrollTo(desired.coerceIn(0, state.maxValue))
        }
        horizontalState?.let { state ->
            // top/center/bottom all sit at UnitPoint x = 0.5: center the cross run.
            val desired = state.value + position.x.roundToInt() -
                anchorOffset(ScrollAnchor.Center, container.size.width, target.size.width)
            state.animateScrollTo(desired.coerceIn(0, state.maxValue))
        }
    }
}

/**
 * A lazy container: its hoisted [LazyListState] plus the id-to-row-index
 * resolver over the authored children. `animateScrollToItem` brings the row
 * to the viewport start (the `top` anchor and the only stop an uncomposed
 * row supports); for `center` / `bottom` the now-composed row's real size is
 * read back from `layoutInfo` and the residual animated.
 */
internal class LazyScrollHandle(
    private val state: LazyListState,
    private val vertical: Boolean,
    private val resolveIndex: (Int) -> Int?,
) {
    fun indexOf(id: Int): Int? = resolveIndex(id)

    suspend fun scrollToIndex(index: Int, anchor: ScrollAnchor) {
        state.animateScrollToItem(index)
        // A horizontal run always centers (UnitPoint x = 0.5 across the set).
        val effective = if (vertical) anchor else ScrollAnchor.Center
        if (effective == ScrollAnchor.Top) return
        val info = state.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index } ?: return
        val viewport = state.layoutInfo.viewportEndOffset - state.layoutInfo.viewportStartOffset
        val desired = anchorOffset(effective, viewport, info.size) + state.layoutInfo.viewportStartOffset
        state.animateScrollBy((info.offset - desired).toFloat())
    }
}

/**
 * The viewport offset (px from the viewport start) where the target's leading
 * edge lands for [anchor]. Clamped at 0 so an item taller than the viewport
 * pins to the top, which is what SwiftUI does too.
 */
internal fun anchorOffset(anchor: ScrollAnchor, viewportExtent: Int, itemExtent: Int): Int =
    when (anchor) {
        ScrollAnchor.Top -> 0
        ScrollAnchor.Center -> ((viewportExtent - itemExtent) / 2).coerceAtLeast(0)
        ScrollAnchor.Bottom -> (viewportExtent - itemExtent).coerceAtLeast(0)
    }

/**
 * The index of the direct child of a lazy container whose subtree contains
 * [id] - the row `animateScrollToItem` scrolls to. Matches SwiftUI: an id
 * deep inside a lazy row scrolls the row. Searches `children` and the named
 * `content` container recursively; `null` when no row owns the id.
 */
internal fun lazyChildIndexOf(children: List<ActionUIElement>, id: Int): Int? {
    val index = children.indexOfFirst { containsElementID(it, id) }
    return if (index >= 0) index else null
}

private fun containsElementID(element: ActionUIElement, id: Int): Boolean {
    if (element.id == id) return true
    if (element.content?.let { containsElementID(it, id) } == true) return true
    return element.children.orEmpty().any { containsElementID(it, id) }
}

/**
 * The `scrollTo` target id. Apple parity (`ScrollViewReader.swift`
 * `validateProperties`): must be an Int - a string, fraction, boolean, or
 * object warns and is ignored. Absent is simply no scroll request.
 */
internal fun resolveScrollTarget(properties: JsonObject?, logger: ActionUILogger? = null): Int? {
    val raw = properties?.get("scrollTo") ?: return null
    val value = (raw as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
    if (value == null) {
        logger?.log("ScrollViewReader scrollTo must be an Int; ignoring", LoggerLevel.warning)
        return null
    }
    return value
}

/**
 * The `anchor` property. Apple parity: `top` / `center` / `bottom`, default
 * `center`; an unknown *string* warns and defaults, a non-string is silently
 * ignored (the Apple validator only checks string values).
 */
internal fun resolveScrollAnchor(properties: JsonObject?, logger: ActionUILogger? = null): ScrollAnchor {
    val raw = (properties?.get("anchor") as? JsonPrimitive)?.takeIf { it.isString }?.content
        ?: return ScrollAnchor.Center
    return when (raw) {
        "top" -> ScrollAnchor.Top
        "center" -> ScrollAnchor.Center
        "bottom" -> ScrollAnchor.Bottom
        else -> {
            logger?.log("ScrollViewReader anchor '$raw' invalid; defaulting to 'center'", LoggerLevel.warning)
            ScrollAnchor.Center
        }
    }
}

/**
 * Enrolls a plain scroll container in the enclosing reader (no-op outside
 * one). Returns the modifier that captures the container's viewport
 * coordinates; the caller appends it to the scroll container's modifier
 * chain.
 */
@Composable
internal fun rememberPlainScrollRegistration(
    verticalState: ScrollState?,
    horizontalState: ScrollState?,
): Modifier {
    val reader = LocalScrollViewReaderState.current ?: return Modifier
    val handle = remember(reader, verticalState, horizontalState) {
        PlainScrollHandle(verticalState, horizontalState)
    }
    DisposableEffect(reader, handle) {
        reader.registerPlainHandle(handle)
        onDispose { reader.unregisterPlainHandle(handle) }
    }
    return Modifier.onGloballyPositioned { handle.coordinates = it }
}

/**
 * Enrolls a lazy container in the enclosing reader (no-op outside one). The
 * id-to-index resolver reads the latest authored children through
 * [rememberUpdatedState], so a recomposed element keeps the handle current.
 */
@Composable
internal fun RegisterLazyScrollHandle(element: ActionUIElement, state: LazyListState, vertical: Boolean) {
    val reader = LocalScrollViewReaderState.current ?: return
    val children by rememberUpdatedState(element.children.orEmpty())
    DisposableEffect(reader, state, vertical) {
        val handle = LazyScrollHandle(state, vertical) { id -> lazyChildIndexOf(children, id) }
        reader.registerLazyHandle(handle)
        onDispose { reader.unregisterLazyHandle(handle) }
    }
}

/**
 * Registers the element's layout coordinates as a scroll target when a reader
 * is in scope and the element has a positive id; identity otherwise. Called
 * at the shared build entry point (`BuildViewWithModifiers`), the one place
 * every rendered element passes through.
 */
@Composable
internal fun scrollTargetModifier(element: ActionUIElement, modifier: Modifier): Modifier {
    val reader = LocalScrollViewReaderState.current ?: return modifier
    if (element.id <= 0) return modifier
    DisposableEffect(reader, element.id) {
        onDispose { reader.targetCoordinates.remove(element.id) }
    }
    return modifier.onGloballyPositioned { reader.targetCoordinates[element.id] = it }
}
