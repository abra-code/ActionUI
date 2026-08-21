package com.abracode.actionui.Views

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.LocalActionUIInputEnabled
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.RefreshableScrollContainer
import com.abracode.actionui.Helpers.rememberPlainScrollRegistration
import com.abracode.actionui.Helpers.stringProperty

/**
 * Scrolling viewport around a single child. Mirror of the Apple `ScrollView`
 * element (`ActionUI/Views/ScrollView.swift`), which wraps `SwiftUI.ScrollView`.
 * The first element to read the **single-child `content`** named container (see
 * [ActionUIElement]); its child is supplied under the top-level `content` key,
 * not `children`.
 *
 * Rendered as a [Box] carrying a `verticalScroll` / `horizontalScroll` modifier
 * (or both).
 *
 * **Lazy content.** A `Lazy*` container is its own scroll viewport on Android
 * (no Apple/web counterpart), so a `ScrollView` wrapping one of the same axis -
 * the ordinary authored idiom, since Apple and web REQUIRE the wrapper - would
 * nest two scrollers and starve the child of a bounded viewport. This element
 * stands its own scroll down on that axis and lets the child have it
 * ([selfScrollingAxis]).
 *
 * **Unbounded-axis guard.** A Compose scroll modifier requires a *bounded* main
 * axis - it throws `IllegalStateException` ("scrollable component was measured
 * with an infinity maximum ... constraints") if measured unbounded. The usual
 * trigger is a `ScrollView` nested in another scroll of the same axis (the demo
 * shell already scrolls vertically, so a `ScrollView` with no bounding `frame`
 * placed in a document is a vertical-in-vertical nest). Rather than crash the
 * whole render from one bad document, this element reads its incoming
 * constraints ([BoxWithConstraints]) and **drops any scroll axis that is
 * unbounded** ([resolveAppliedScroll]): that axis defers to the enclosing scroll
 * (which handles the overflow), matching SwiftUI's tolerance of nested
 * ScrollViews. A bounding `frame` (height for vertical, width for horizontal)
 * re-enables the element's own scroll. A dropped axis warns once.
 *
 * **Supported properties.**
 *   * `axis` - `"vertical"` (default), `"horizontal"`, or `"both"`, resolved by
 *     [resolveScrollAxis]; an unrecognized value warns and falls back to
 *     vertical, matching the Apple validator.
 *   * `showsIndicators` - accepted for cross-platform parity but **not visually
 *     honored**: Compose's scroll modifiers draw no persistent scrollbar on
 *     Android and expose no toggle, so there is nothing to show or hide (see the
 *     divergence note in `Private/Android_Porting_Notes.md`).
 *   * `onRefreshActionID` - when set, wraps the viewport in a Material3 pull-to-refresh box
 *     (see [RefreshableScrollContainer]); a pull fires the actionID and the indicator stays
 *     until the client updates this view or anything inside it. Apple parity is `.refreshable`.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]), notably `frame` to bound the viewport.
 *
 * **Single child.** On Android `content` is one element (never an array); to
 * scroll several views, wrap them in a `VStack` / `HStack` / `Group`. When no
 * `content` is present the ScrollView renders nothing.
 */
object ScrollView : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val content = element.content ?: return
        val builder = ActionUIRegistry.lookup(content.type) ?: return

        val axis = resolveScrollAxis(element.properties?.stringProperty("axis"), logger)

        // A hidden scroll container must not consume touch (Apple/web make `hidden`
        // non-interactive) - see ListView and Missing_Features #34. When hidden, render a bare
        // Box that reserves the viewport size but carries no scroll/pointer node, so hit-testing
        // falls through to a visible sibling behind it in an overlapping ZStack.
        if (!LocalActionUIInputEnabled.current) {
            Box(modifier)
            return
        }

        val verticalState = rememberScrollState()
        val horizontalState = rememberScrollState()

        // Read the incoming constraints so an unbounded scroll axis can be dropped
        // (see the class note) instead of crashing the scroll modifier.
        BoxWithConstraints(modifier = modifier) {
            // A content child that is its own viewport on this axis (a Lazy* container)
            // takes the scroll instead - see resolveAppliedScroll.
            val deferred = selfScrollingAxis(content.type)
            val applied = resolveAppliedScroll(
                axis, constraints.hasBoundedHeight, constraints.hasBoundedWidth, deferred,
            )

            val droppedVertical = axis != ScrollAxis.Horizontal && !applied.vertical &&
                deferred != ScrollAxis.Vertical
            val droppedHorizontal = axis != ScrollAxis.Vertical && !applied.horizontal &&
                deferred != ScrollAxis.Horizontal
            LaunchedEffect(droppedVertical, droppedHorizontal) {
                if (droppedVertical || droppedHorizontal) {
                    logger.log(
                        "ScrollView is unbounded on its scroll axis (a ScrollView nested in " +
                            "another scroll of the same axis?); that axis defers to the enclosing " +
                            "scroll. Add a frame height/width to make this ScrollView scroll itself.",
                        LoggerLevel.warning,
                    )
                }
            }

            // Enroll in an enclosing ScrollViewReader (identity modifier outside
            // one) so the reader can drive this viewport's ScrollStates - only for
            // the axes we actually scroll. Must sit BEFORE the scroll modifiers in
            // the chain: it captures the viewport coordinates, against which target
            // positions move as the content scrolls (inside the scroll modifier they
            // would be static content coordinates and the reader's offset math would
            // double-count the current scroll value).
            val readerModifier = rememberPlainScrollRegistration(
                verticalState = verticalState.takeIf { applied.vertical },
                horizontalState = horizontalState.takeIf { applied.horizontal },
            )
            var scrollModifier = readerModifier
            if (applied.vertical) scrollModifier = scrollModifier.verticalScroll(verticalState)
            if (applied.horizontal) scrollModifier = scrollModifier.horizontalScroll(horizontalState)

            // Pull-to-refresh wraps the scroll Box when onRefreshActionID is set; otherwise
            // this renders the Box unchanged (see RefreshableScrollContainer).
            RefreshableScrollContainer(element) {
                Box(modifier = scrollModifier) {
                    ProvideTextStyleEnvironment(content.properties, logger) {
                        builder.BuildViewWithModifiers(content, Modifier)
                    }
                }
            }
        }
    }
}

/** The scroll directions the Android renderer supports. */
internal enum class ScrollAxis { Vertical, Horizontal, Both }

/** Which scroll axes [ScrollView] actually applies (see its unbounded-axis guard). */
internal data class ScrollAxesApplied(val vertical: Boolean, val horizontal: Boolean)

/**
 * The axis a given element type scrolls BY ITSELF, or `null` for the ordinary
 * case of an element that simply grows and lets an ancestor scroll it.
 *
 * The `Lazy*` containers are both the lazy builder and the scroll viewport on
 * their main axis - a Compose trait with no Apple or web counterpart, where a
 * `LazyVGrid` is inert layout inside a `ScrollView`. That difference is why
 * [ScrollView] has to know about them (see [resolveAppliedScroll]); `List` is
 * deliberately NOT here, because a template List inside a non-scrolling parent
 * is its own resolved case (Missing_Features #34).
 */
internal fun selfScrollingAxis(type: String?): ScrollAxis? = when (type) {
    "LazyVGrid", "LazyVStack" -> ScrollAxis.Vertical
    "LazyHGrid", "LazyHStack" -> ScrollAxis.Horizontal
    else -> null
}

/**
 * Decides which scroll axes [ScrollView] applies, given the requested [axis],
 * whether the incoming constraints bound each axis ([boundedHeight] /
 * [boundedWidth]), and which axis the single `content` child scrolls by itself
 * ([contentSelfScrolls], from [selfScrollingAxis]).
 *
 * Two reasons to drop a requested axis:
 *
 *  * **Unbounded.** Applying `verticalScroll` / `horizontalScroll` to an infinite
 *    constraint throws in Compose, so the enclosing scroll handles that overflow
 *    instead.
 *  * **Deferred to the content.** A `ScrollView` wrapping a `Lazy*` container of
 *    the same axis is the authored idiom on Apple and web, where the wrapper is
 *    what scrolls. On Android the child scrolls itself, so nesting both means two
 *    scrollers on one axis - and, worse, the child measures against an infinite
 *    height and falls back to its fixed default extent, letterboxing a
 *    full-screen grid. Standing down here hands the child a bounded viewport,
 *    which is the arrangement the JSON describes.
 *
 * Pure, so it is unit-testable without a Compose host.
 */
internal fun resolveAppliedScroll(
    axis: ScrollAxis,
    boundedHeight: Boolean,
    boundedWidth: Boolean,
    contentSelfScrolls: ScrollAxis? = null,
): ScrollAxesApplied {
    val wantsVertical = axis != ScrollAxis.Horizontal && contentSelfScrolls != ScrollAxis.Vertical
    val wantsHorizontal = axis != ScrollAxis.Vertical && contentSelfScrolls != ScrollAxis.Horizontal
    return ScrollAxesApplied(
        vertical = wantsVertical && boundedHeight,
        horizontal = wantsHorizontal && boundedWidth,
    )
}

/**
 * Maps the JSON `axis` to a [ScrollAxis]. `null`/`"vertical"` -> [ScrollAxis.Vertical],
 * `"horizontal"` -> [ScrollAxis.Horizontal], `"both"` -> [ScrollAxis.Both]; any
 * other value warns and falls back to vertical, parity with the Apple
 * `validateProperties` default. Pure (logging aside) so it is unit-testable.
 */
internal fun resolveScrollAxis(raw: String?, logger: ActionUILogger): ScrollAxis = when (raw) {
    null, "vertical" -> ScrollAxis.Vertical
    "horizontal" -> ScrollAxis.Horizontal
    "both" -> ScrollAxis.Both
    else -> {
        logger.log("ScrollView axis '$raw' invalid; defaulting to 'vertical'", LoggerLevel.warning)
        ScrollAxis.Vertical
    }
}
