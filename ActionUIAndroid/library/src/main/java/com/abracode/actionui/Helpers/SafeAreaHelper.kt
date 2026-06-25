package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.applyInnerProperties
import com.abracode.actionui.Common.applyOuterProperties
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull

/**
 * Safe-area modifiers - the Android side of SwiftUI's `.ignoresSafeArea` / `.safeAreaInset`
 * (`ActionUI/Views/View.swift`).
 *
 * Android draws edge-to-edge (the host's `enableEdgeToEdge()`), so a bare view already extends
 * into the safe area - the *opposite* default to SwiftUI. So here:
 *  - **ignoresSafeArea** consumes the chosen safe-drawing edges ([consumeWindowInsets]) so a
 *    descendant that does respect the safe area (a `safeAreaInset` bar) no longer pads for them.
 *    A plain view is unaffected (it was already edge-to-edge).
 *  - **safeAreaInset** is the load-bearing half: it places the inset view at an edge and lets the
 *    main content take the rest, with the bar padded by that edge's safe-drawing inset
 *    ([windowInsetsPadding]) so it clears the system bar - the native bottom-bar idiom.
 */

/** The `ignoresSafeArea` modifier for the element's carrier: consumes the chosen safe-drawing edges.
 *  @Composable because `WindowInsets.safeDrawing` reads the composition-local insets. */
@Composable
internal fun ignoresSafeAreaModifier(properties: JsonObject?): Modifier {
    val value = properties?.get("ignoresSafeArea") ?: return Modifier
    val edges: String = when {
        value is JsonPrimitive && value.booleanOrNull == true -> "all"
        value is JsonObject -> (value["edges"] as? JsonPrimitive)?.contentOrNull ?: "all"
        else -> return Modifier   // false, or an unexpected shape -> nothing to ignore
    }
    val insets = if (edges == "all") WindowInsets.safeDrawing
    else WindowInsets.safeDrawing.only(safeAreaSides(edges))
    return Modifier.consumeWindowInsets(insets)
}

/**
 * The default safe-area inset for a CHROME-LESS document root (no `toolbar` /
 * `navigationTitle` - e.g. a plain `VStack` root). SwiftUI insets the root content by
 * the safe area automatically; Android draws edge-to-edge, so without this a bare root
 * sits under the status / navigation bars (and behind a display cutout). Returns the
 * `safeDrawing` padding so the root matches SwiftUI - UNLESS the root already manages
 * its own insets: it declares `ignoresSafeArea` (its [ignoresSafeAreaModifier] then
 * consumes the chosen edges) or a `safeAreaInset` (which needs the raw insets to place
 * its bar). A root WITH toolbar chrome is excluded by the caller - its `Scaffold`
 * already insets the system bars. `safeDrawing` includes the IME, so a focused field
 * is kept above the keyboard, matching SwiftUI's default keyboard avoidance.
 */
@Composable
internal fun rootSafeAreaModifier(element: ActionUIElement): Modifier {
    val managesOwnInsets = element.safeAreaInset != null || run {
        val v = element.properties?.get("ignoresSafeArea")
        (v is JsonPrimitive && v.booleanOrNull == true) || v is JsonObject
    }
    return if (managesOwnInsets) Modifier else Modifier.windowInsetsPadding(WindowInsets.safeDrawing)
}

/** Wraps [element] so its `safeAreaInset` view sits at an edge and the content takes the rest. */
@Composable
internal fun ActionUIViewConstruction.BuildViewWithSafeAreaInset(
    element: ActionUIElement,
    modifier: Modifier,
    animator: ElementAnimator?,
) {
    val logger = LocalActionUILogger.current
    val inset = element.safeAreaInset ?: run {
        BuildViewWithDecorations(element, modifier.applyOuterProperties(element.properties, logger, animator), animator)
        return
    }
    val edge = inset.properties?.stringProperty("safeAreaEdge") ?: "bottom"
    val barSide = when (edge) {
        "top" -> WindowInsetsSides.Top
        "leading" -> WindowInsetsSides.Start
        "trailing" -> WindowInsetsSides.End
        else -> WindowInsetsSides.Bottom
    }
    // The inset bar clears that edge's system inset; the content fills the remaining space.
    val bar: @Composable () -> Unit = {
        ElementContent(inset, logger, Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(barSide)))
    }
    val barFirst = edge == "top" || edge == "leading"
    // The wrapper (Column/Row) carries the element's full size + decoration (frame / background /
    // cornerRadius via applyInnerProperties) so the container is bounded: the weighted bar/content split
    // needs a height to divide, and the frame is an *inner* property, so it must sit on the wrapper here
    // rather than on the content (where it cannot size the Column). The content is then built bare and
    // greedy, filling the remaining (weighted) space. The bound comes from the frame, so an unbounded
    // parent (a scrolling demo host) needs one - use frame.maxHeight "infinity" to fill a bounded
    // window root, as elsewhere.
    val carrier = modifier
        .applyOuterProperties(element.properties, logger, animator)
        .applyInnerProperties(element.properties, logger, animator, MaterialTheme.colorScheme)

    if (edge == "top" || edge == "bottom") {
        Column(carrier) {
            if (barFirst) bar()
            Box(Modifier.weight(1f).fillMaxWidth()) {
                BuildView(element, Modifier.fillMaxSize())
            }
            if (!barFirst) bar()
        }
    } else {
        Row(carrier) {
            if (barFirst) bar()
            Box(Modifier.weight(1f).fillMaxHeight()) {
                BuildView(element, Modifier.fillMaxSize())
            }
            if (!barFirst) bar()
        }
    }
}

private fun safeAreaSides(edges: String): WindowInsetsSides = when (edges) {
    "top" -> WindowInsetsSides.Top
    "bottom" -> WindowInsetsSides.Bottom
    "leading" -> WindowInsetsSides.Start
    "trailing" -> WindowInsetsSides.End
    "horizontal" -> WindowInsetsSides.Horizontal
    "vertical" -> WindowInsetsSides.Vertical
    else -> WindowInsetsSides.Horizontal + WindowInsetsSides.Vertical
}
