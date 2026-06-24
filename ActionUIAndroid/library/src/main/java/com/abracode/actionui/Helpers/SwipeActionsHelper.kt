package com.abracode.actionui.Helpers

import androidx.compose.animation.core.animate
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUIImageRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.applyOuterProperties
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * The `swipeActions` modifier - the Android mirror of Apple's `.swipeActions`
 * (`View.swift` applyModifiers, `Helpers/SwipeActionsHelper.swift`).
 *
 * **Why a subview slot, not a property array.** SwiftUI's
 * `.swipeActions(edge:allowsFullSwipe:)` is a ViewBuilder of Buttons. ActionUI models
 * it like `contextMenu`: `swipeActions` is an array subview of real `Button` elements,
 * each carrying its own title / systemImage / role / tint / actionID plus an optional
 * `edge` ("leading"/"trailing", default trailing) and `allowsFullSwipe` (default true).
 *
 * **Gesture is the platform idiom, not a port.** Apple reveals the buttons on a
 * horizontal swipe of a List row; the Android idiom is the same swipe-to-reveal
 * (Gmail-style), built on the first-party [draggable] gesture: the row content
 * translates with the drag, the edge's action Buttons sit behind it (leading pinned to
 * the start, trailing to the end) and are revealed as the row slides. Tapping a revealed
 * Button fires its `actionID` and closes the row; a full swipe of an `allowsFullSwipe`
 * edge (past half the row width) fires that edge's first Button - the iOS full-swipe
 * shortcut. The host decides what the action does (delete the row, etc.); the row itself
 * snaps closed, never self-removing.
 *
 * Apple honors `.swipeActions` only inside a List; here the wrapper applies wherever the
 * element declares it, so a swipeable row works through the normal List child path.
 */
@Composable
internal fun ActionUIViewConstruction.BuildViewWithSwipeActions(
    element: ActionUIElement,
    modifier: Modifier,
    animator: ElementAnimator?,
) {
    val logger = LocalActionUILogger.current
    val all = element.swipeActions.orEmpty()
    val leading = all.filter { swipeEdge(it) == "leading" }
    val trailing = all.filter { swipeEdge(it) == "trailing" }
    if (leading.isEmpty() && trailing.isEmpty()) {
        BuildViewWithDecorations(element, modifier.applyOuterProperties(element.properties, logger, animator), animator)
        return
    }

    // A full swipe fires that edge's first button, so allowsFullSwipe for an edge is read
    // from the first button declaring it on that edge (default true), mirroring the Swift side.
    val leadingFull = leading.firstNotNullOfOrNull { it.properties?.booleanProperty("allowsFullSwipe") } ?: true
    val trailingFull = trailing.firstNotNullOfOrNull { it.properties?.booleanProperty("allowsFullSwipe") } ?: true

    val density = LocalDensity.current
    val actionWidthPx = with(density) { ACTION_WIDTH.toPx() }
    val leadingRevealPx = actionWidthPx * leading.size
    val trailingRevealPx = actionWidthPx * trailing.size

    var offsetX by remember { mutableFloatStateOf(0f) }
    var rowWidthPx by remember { mutableFloatStateOf(0f) }
    val scope = rememberCoroutineScope()
    val close: () -> Unit = { scope.launch { animate(offsetX, 0f) { v, _ -> offsetX = v } } }

    fun fire(button: ActionUIElement) {
        button.properties?.stringProperty("actionID")?.let {
            ActionUIModel.actionHandler(it, viewID = button.id, viewPartID = 0)
        }
    }

    Box(
        modifier
            .fillMaxWidth()
            .applyOuterProperties(element.properties, logger, animator)
            .onSizeChanged { rowWidthPx = it.width.toFloat() }
    ) {
        // Behind the row: the edge's action buttons, revealed as the row slides off them.
        if (leading.isNotEmpty()) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.Start) {
                leading.forEach { SwipeActionButton(it, logger, close) }
            }
        }
        if (trailing.isNotEmpty()) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.End) {
                trailing.forEach { SwipeActionButton(it, logger, close) }
            }
        }
        // The row content: opaque (so the buttons hide when closed) and translated by the drag.
        // A comfortable minimum height gives the revealed action buttons room for their icon
        // over the title (a one-line Label alone is too short - the glyph would clip); the
        // content is centered in it so the row text still sits on the vertical midline.
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = ROW_MIN_HEIGHT)
                .offset { IntOffset(offsetX.roundToInt(), 0) }
                .background(MaterialTheme.colorScheme.surface)
                .draggable(
                    orientation = Orientation.Horizontal,
                    state = rememberDraggableState { delta ->
                        val min = if (trailing.isEmpty()) 0f else -rowWidthPx
                        val max = if (leading.isEmpty()) 0f else rowWidthPx
                        offsetX = (offsetX + delta).coerceIn(min, max)
                    },
                    onDragStopped = {
                        val x = offsetX
                        val target = when {
                            x > 0f -> when { // leading side
                                leadingFull && rowWidthPx > 0f && x > rowWidthPx * FULL_SWIPE_FRACTION -> {
                                    fire(leading.first()); 0f
                                }
                                x > leadingRevealPx * 0.5f -> leadingRevealPx
                                else -> 0f
                            }
                            x < 0f -> when { // trailing side
                                trailingFull && rowWidthPx > 0f && -x > rowWidthPx * FULL_SWIPE_FRACTION -> {
                                    fire(trailing.first()); 0f
                                }
                                -x > trailingRevealPx * 0.5f -> -trailingRevealPx
                                else -> 0f
                            }
                            else -> 0f
                        }
                        animate(offsetX, target) { v, _ -> offsetX = v }
                    },
                ),
            contentAlignment = Alignment.CenterStart,
        ) {
            BuildViewWithDecorations(element, Modifier, animator)
        }
    }
}

/** One revealed swipe-action button: a tinted, full-height column with the icon over the title. */
@Composable
private fun SwipeActionButton(
    button: ActionUIElement,
    logger: ActionUILogger,
    close: () -> Unit,
) {
    val props = button.properties
    val title = props?.stringProperty("title").orEmpty()
    val role = props?.stringProperty("role")
    val tintName = props?.stringProperty("tint")
    // role:destructive paints the Material error color (the red destructive swipe); an explicit
    // tint paints that color (named/hex OR an Apple semantic style via resolveColorOrSemantic);
    // otherwise the secondary container, like a neutral Material action.
    val background = when {
        role == "destructive" -> MaterialTheme.colorScheme.error
        tintName != null -> resolveColorOrSemantic(tintName, MaterialTheme.colorScheme) ?: MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.secondary
    }
    val imageRegistry = LocalActionUIImageRegistry.current
    val iconSource = remember(props, imageRegistry) { selectLabelIcon(props, "assetImage", "Swipe action", logger, imageRegistry) }

    Column(
        Modifier
            .width(ACTION_WIDTH)
            .fillMaxHeight()
            .background(background)
            .clickable {
                props?.stringProperty("actionID")?.let {
                    ActionUIModel.actionHandler(it, viewID = button.id, viewPartID = 0)
                }
                close()
            }
            .padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        iconSource?.let {
            LabelIcon(
                source = it,
                imageScale = props?.stringProperty("imageScale"),
                contentDescription = title,
                elementName = "Swipe action",
                tint = Color.White,
                logger = logger,
            )
        }
        if (title.isNotEmpty()) {
            Text(title, color = Color.White, fontSize = 12.sp, textAlign = TextAlign.Center)
        }
    }
}

/** The button's declared swipe edge, defaulting to trailing (SwiftUI's default). */
private fun swipeEdge(button: ActionUIElement): String =
    if (button.properties?.stringProperty("edge") == "leading") "leading" else "trailing"

private val ACTION_WIDTH = 84.dp
/** Minimum row height, so a revealed action's icon-over-title has room (a one-line Label clips it). */
private val ROW_MIN_HEIGHT = 56.dp
/** Drag past this fraction of the row width on an allowsFullSwipe edge fires its first button. */
private const val FULL_SWIPE_FRACTION = 0.5f
