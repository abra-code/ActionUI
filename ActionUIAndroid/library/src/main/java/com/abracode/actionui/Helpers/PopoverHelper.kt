package com.abracode.actionui.Helpers

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonObject

/**
 * The element-level `popover` subview - the anchored counterpart of the
 * `sheet` / `fullScreenCover` modals in `ElementModalHost.kt` and the Android
 * mirror of Apple's `PopoverModifierView` (`ActionUI/Helpers/PopoverHelper.swift`).
 *
 * **Why this one is composed at the carrier, not in a window-level host.**
 * Unlike a sheet or a dialog, a popover is *anchored*: it positions against the
 * carrier's on-screen bounds. A Compose [Popup] anchors to the layout node it
 * is composed in - the same mechanism `DropdownMenu` uses - so the wrap must
 * happen where the carrier is built. [BuildViewWithPopover] is that seam: every
 * container child loop calls it instead of `BuildView`, and it is an exact
 * pass-through for the overwhelmingly common carrier-less element. (`template`
 * content keeps calling `BuildView` directly - per-row instances have no
 * registered ViewModel to hold presentation state, same exclusion as the
 * modals.)
 *
 * **Presentation state - Apple contract, key for key.** The carrier's
 * `states["popoverVisible"]` drives visibility. A tap on a non-`Button` carrier
 * toggles it (Apple's `addTapGesture: element.type != "Button"`); a `Button`
 * carrier toggles in its own `onClick` (`Views/Button.kt`), so no gesture is
 * added that could double-fire. `popoverActionID` fires when the popover is
 * *shown* (either path); hosts can also drive both directions via
 * `ActionUIModel.setElementState(viewID, "popoverVisible", ...)`. Outside-tap
 * and back-press dismiss (the popup is focusable), like tapping outside an
 * iOS popover.
 *
 * **Placement.** `popoverArrowEdge` names the *anchor's* edge the arrow
 * attaches to (SwiftUI's `arrowEdge`), so the surface sits on that side of the
 * carrier: `top` -> above it, `bottom` -> below, `leading`/`trailing` ->
 * beside it (layout-direction aware), centered on the cross axis and clamped
 * to the window ([popoverPosition], pure and unit-tested). Divergence: no arrow -
 * Android's anchored surfaces (menus, autocomplete) draw none, so the popover
 * is an elevated Material shape like a `DropdownMenu` container.
 */
@Composable
fun ActionUIViewConstruction.BuildViewWithPopover(element: ActionUIElement, modifier: Modifier) {
    val popoverElement = element.popover
    if (popoverElement == null) {
        BuildView(element, modifier)
        return
    }

    val logger = LocalActionUILogger.current
    val carrierModel = LocalWindowModel.current?.viewModels?.get(element.id)
    if (carrierModel == null) {
        // No registered ViewModel (no window, or an unregistered context) means
        // no state to hold the presentation flag; render the carrier plain.
        logger.log(
            "Popover on element id ${element.id} has no registered state; ignoring the subview.",
            LoggerLevel.warning,
        )
        BuildView(element, modifier)
        return
    }

    val popoverActionID = element.properties?.stringProperty("popoverActionID")
    val arrowEdge = parsePopoverArrowEdge(element.properties, logger)

    fun toggle() {
        val willShow = !(carrierModel.states[POPOVER_VISIBLE_STATE_KEY] as? Boolean ?: false)
        carrierModel.states[POPOVER_VISIBLE_STATE_KEY] = willShow
        if (willShow && popoverActionID != null) {
            ActionUIModel.actionHandler(popoverActionID, viewID = element.id, viewPartID = 0)
        }
    }

    // Non-Button carriers toggle on tap; pointerInput (not clickable) so there
    // is no ripple, matching SwiftUI's onTapGesture. A Button consumes its own
    // taps anyway and toggles in onClick.
    val tapModifier = if (element.type != "Button") {
        Modifier.pointerInput(element.id) { detectTapGestures { toggle() } }
    } else {
        Modifier
    }

    // The Box is the anchor node: the carrier's modifier chain moves onto it
    // (so weight/align parent data still face the real parent layout) and the
    // Popup anchors to its bounds.
    Box(modifier.then(tapModifier)) {
        BuildView(element, Modifier)
        val visible = carrierModel.states[POPOVER_VISIBLE_STATE_KEY] as? Boolean ?: false
        if (visible) {
            Popup(
                popupPositionProvider = remember(arrowEdge) { PopoverPositionProvider(arrowEdge) },
                onDismissRequest = { carrierModel.states[POPOVER_VISIBLE_STATE_KEY] = false },
                properties = PopupProperties(focusable = true),
            ) {
                Surface(
                    shape = MaterialTheme.shapes.medium,
                    tonalElevation = 3.dp,
                    shadowElevation = 3.dp,
                ) {
                    ModalContent(popoverElement, logger)
                }
            }
        }
    }
}

/** The `states` key gating an element-level popover; Apple's `PopoverHelper.swift` key. */
const val POPOVER_VISIBLE_STATE_KEY = "popoverVisible"

/** The anchor edge the (conceptual) arrow attaches to - SwiftUI's `arrowEdge` vocabulary. */
internal enum class PopoverEdge { TOP, BOTTOM, LEADING, TRAILING }

/**
 * Parses `popoverArrowEdge` with Apple's validation behavior: an unrecognized
 * value warns and falls back to `top` (the SwiftUI default).
 */
internal fun parsePopoverArrowEdge(properties: JsonObject?, logger: ActionUILogger?): PopoverEdge {
    val raw = properties?.stringProperty("popoverArrowEdge") ?: return PopoverEdge.TOP
    return when (raw.lowercase()) {
        "top" -> PopoverEdge.TOP
        "bottom" -> PopoverEdge.BOTTOM
        "leading" -> PopoverEdge.LEADING
        "trailing" -> PopoverEdge.TRAILING
        else -> {
            logger?.log(
                "Invalid popoverArrowEdge '$raw'; expected one of [top, bottom, leading, trailing], defaulting to 'top'",
                LoggerLevel.warning,
            )
            PopoverEdge.TOP
        }
    }
}

/** Positions the popup per [popoverPosition]; the [PopupPositionProvider] shim. */
internal class PopoverPositionProvider(private val edge: PopoverEdge) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset = popoverPosition(anchorBounds, windowSize, layoutDirection, popupContentSize, edge)
}

/**
 * The popover's window position for an anchor and arrow edge. The edge names
 * the anchor's side the arrow attaches to, so the popover lands on *that*
 * side: `top` -> above the anchor, `bottom` -> below, `leading` -> before it
 * in the layout direction, `trailing` -> after it. Centered on the cross axis,
 * then clamped into the window (an off-screen popover slides in rather than
 * clipping - SwiftUI repositions similarly when the preferred edge lacks room).
 */
internal fun popoverPosition(
    anchorBounds: IntRect,
    windowSize: IntSize,
    layoutDirection: LayoutDirection,
    popupSize: IntSize,
    edge: PopoverEdge,
): IntOffset {
    val ltr = layoutDirection == LayoutDirection.Ltr
    val resolved = when (edge) {
        PopoverEdge.LEADING -> if (ltr) PopoverEdge.LEADING else PopoverEdge.TRAILING
        PopoverEdge.TRAILING -> if (ltr) PopoverEdge.TRAILING else PopoverEdge.LEADING
        else -> edge
    }
    val centeredX = anchorBounds.left + (anchorBounds.width - popupSize.width) / 2
    val centeredY = anchorBounds.top + (anchorBounds.height - popupSize.height) / 2
    val (x, y) = when (resolved) {
        PopoverEdge.TOP -> centeredX to anchorBounds.top - popupSize.height
        PopoverEdge.BOTTOM -> centeredX to anchorBounds.bottom
        PopoverEdge.LEADING -> anchorBounds.left - popupSize.width to centeredY
        PopoverEdge.TRAILING -> anchorBounds.right to centeredY
    }
    return IntOffset(
        x.coerceIn(0, maxOf(0, windowSize.width - popupSize.width)),
        y.coerceIn(0, maxOf(0, windowSize.height - popupSize.height)),
    )
}
