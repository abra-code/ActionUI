package com.abracode.actionui.Views

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
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
 * (or both). Unlike the lazy stacks, these modifiers do not require a bounded
 * main axis: the Box is sized by its parent and lets the child overflow and
 * scroll, so no default extent is needed.
 *
 * **Supported properties.**
 *   * `axis` - `"vertical"` (default), `"horizontal"`, or `"both"`, resolved by
 *     [resolveScrollAxis]; an unrecognized value warns and falls back to
 *     vertical, matching the Apple validator.
 *   * `showsIndicators` - accepted for cross-platform parity but **not visually
 *     honored**: Compose's scroll modifiers draw no persistent scrollbar on
 *     Android and expose no toggle, so there is nothing to show or hide (see the
 *     divergence note in `Private/Android_Porting_Notes.md`).
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

        val verticalState = rememberScrollState()
        val horizontalState = rememberScrollState()

        // Enroll in an enclosing ScrollViewReader (identity modifier outside
        // one) so the reader can drive this viewport's ScrollStates. Must sit
        // BEFORE the scroll modifiers in the chain: it captures the viewport
        // coordinates, against which target positions move as the content
        // scrolls (inside the scroll modifier they would be static content
        // coordinates and the reader's offset math would double-count the
        // current scroll value).
        val readerModifier = rememberPlainScrollRegistration(
            verticalState = verticalState.takeIf { axis != ScrollAxis.Horizontal },
            horizontalState = horizontalState.takeIf { axis != ScrollAxis.Vertical },
        )
        val viewportModifier = modifier.then(readerModifier)
        val scrollModifier = when (axis) {
            ScrollAxis.Vertical -> viewportModifier.verticalScroll(verticalState)
            ScrollAxis.Horizontal -> viewportModifier.horizontalScroll(horizontalState)
            ScrollAxis.Both -> viewportModifier.verticalScroll(verticalState).horizontalScroll(horizontalState)
        }

        Box(modifier = scrollModifier) {
            ProvideTextStyleEnvironment(content.properties, logger) {
                builder.BuildViewWithModifiers(content, Modifier)
            }
        }
    }
}

/** The scroll directions the Android renderer supports. */
internal enum class ScrollAxis { Vertical, Horizontal, Both }

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
