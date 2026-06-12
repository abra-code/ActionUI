package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.applyInnerProperties
import com.abracode.actionui.Common.applyOuterProperties
import com.abracode.actionui.Common.parseAlignment
import kotlinx.serialization.json.JsonObject

/**
 * The shared build entry point: every container child loop (and every root-like context -
 * window root, navigation screen, modal, toolbar item) calls
 * [BuildViewWithModifiers] instead of `BuildView`. It resolves the element's
 * full modifier pipeline - the common properties (`ModifierResolver`) plus the
 * subview-carrying modifiers, the Android mirror of the view-based modifiers
 * in Apple's `View.swift`:
 *
 *   * `popover` - the anchored presentation; wrapped first (outermost) because
 *     a Compose `Popup` anchors to the layout node it is composed in
 *     (`PopoverHelper.kt`).
 *   * `overlay` / `background` - the decoration subviews, composed here in a
 *     `Box` around the element ([BuildViewWithDecorations]).
 *
 * Callers pass only the scope-restricted parent data (`weight`/`align`, via
 * `buildChildModifier`) or `Modifier`; the element's own properties are
 * resolved HERE, not at the call site, because the decoration wrap must split
 * the chain around its `Box`: the outer half (`applyOuterProperties` -
 * transforms, offset, opacity) lands on the `Box` so decorations move and fade
 * with the carrier, the inner half (`applyInnerProperties` - frame, padding,
 * clip, background color) lands on the element inside so decorations cover
 * the frame-plus-padding box and are not clipped by the carrier's rounding.
 *
 * **Decoration semantics - Apple's `.overlay(alignment:)` / `.background(alignment:)`.**
 * A decoration never affects the carrier's layout size (`matchParentSize`);
 * it is positioned by the `overlayAlignment` / `backgroundAlignment` property
 * (default `center`) against the carrier's box and may overflow it
 * (`wrapContentSize(unbounded = true)` - a 56dp `Circle` behind a 44dp `Text`
 * sticks out on both sides, as SwiftUI's soft proposals allow). Draw order is
 * background, element, overlay - so a `background` sits behind the element's
 * own `background` color fill, exactly Apple's modifier order.
 *
 * Known divergences (documented, demo-invisible):
 *   * The carrier's `cornerRadius`/`clipShape` does not clip the `background`
 *     subview (on Apple it does; the `overlay` is unclipped on both, which is
 *     the visible case - corner badges). Background subviews are typically
 *     self-shaped (`Capsule`, `RoundedRectangle`), where this cannot show.
 *   * Decorations on a `Group` wrap the group as one unit; Apple applies
 *     view-based modifiers on a `Group` to each child separately. (The same
 *     pre-existing divergence as `popover` on a `Group`.)
 *
 * The per-row `template` path is excluded, as for the modals and `popover`:
 * `TemplateHelper` keeps calling `BuildView` directly with a fused chain, and
 * throw-away row instances carry no decoration subviews.
 */
@Composable
fun ActionUIViewConstruction.BuildViewWithModifiers(element: ActionUIElement, modifier: Modifier) {
    if (element.popover != null) {
        // PopoverHelper applies the outer half to the anchor Box itself and
        // routes the carrier through BuildViewWithDecorations.
        BuildViewWithPopover(element, modifier)
        return
    }
    val logger = LocalActionUILogger.current
    BuildViewWithDecorations(element, modifier.applyOuterProperties(element.properties, logger))
}

/**
 * Composes the element's `overlay` / `background` decoration subviews around
 * it (see [BuildViewWithModifiers]); the exact `BuildView` pass-through, plus
 * the inner property half, for the undecorated element. [modifier] must
 * already carry the parent data and the outer property half.
 */
@Composable
internal fun ActionUIViewConstruction.BuildViewWithDecorations(
    element: ActionUIElement,
    modifier: Modifier,
) {
    val logger = LocalActionUILogger.current
    val overlayElement = element.overlay
    val backgroundElement = element.background
    if (overlayElement == null && backgroundElement == null) {
        BuildView(element, modifier.applyInnerProperties(element.properties, logger))
        return
    }

    // The Box sizes to the element alone (matchParentSize children are
    // excluded from its measurement), so decorations never change layout.
    Box(modifier) {
        backgroundElement?.let {
            ElementContent(it, logger, decorationModifier(element.properties, "backgroundAlignment", it, logger))
        }
        BuildView(element, Modifier.applyInnerProperties(element.properties, logger))
        overlayElement?.let {
            ElementContent(it, logger, decorationModifier(element.properties, "overlayAlignment", it, logger))
        }
    }
}

/**
 * Sizes a decoration against the carrier's box and positions it by the
 * alignment property. SwiftUI *proposes* the carrier's size and the decoration
 * may refuse it; Compose constraints are hard caps, so the refusal must be
 * read off the decoration itself:
 *
 *   * No fixed `frame` -> the decoration accepts the proposal: measured with
 *     the carrier's box as its bounds, so a greedy bare shape (`Capsule`,
 *     `RoundedRectangle` - `fillMaxSize`, see `ShapeView.kt`) fills the
 *     decorated box exactly. The badge/card background idiom.
 *   * A fixed `frame` -> the decoration refuses: measured unbounded so its own
 *     size wins and may overflow the carrier, positioned by the alignment
 *     (a 56dp `Circle` behind a 44dp `Text` sticks out, as on Apple). The
 *     oversized-badge idiom. (Greedy `fillMaxSize` content cannot resolve
 *     against unbounded constraints, which is why this path is opt-in by
 *     frame rather than the default.)
 */
private fun BoxScope.decorationModifier(
    properties: JsonObject?,
    key: String,
    decoration: ActionUIElement,
    logger: ActionUILogger?,
): Modifier {
    val alignment = resolveDecorationAlignment(properties, key, logger)
    val frame = decoration.properties?.get("frame") as? JsonObject
    val hasFixedFrame = frame != null && (frame["width"] != null || frame["height"] != null)
    return Modifier.matchParentSize().wrapContentSize(alignment, unbounded = hasFixedFrame)
}

/**
 * Resolves `overlayAlignment` / `backgroundAlignment` with Apple's
 * `resolveAlignment` behavior (`View.swift`): SwiftUI alignment vocabulary
 * (`center`, the four edges - centered on the cross axis - and the four
 * corners), defaulting to `center` when absent, warn-and-center when unknown.
 */
internal fun resolveDecorationAlignment(
    properties: JsonObject?,
    key: String,
    logger: ActionUILogger?,
): Alignment {
    val name = properties?.stringProperty(key) ?: return Alignment.Center
    parseAlignment(name)?.let { return it }
    logger?.log(
        "Unknown alignment '$name' for property '$key'. Defaulting to 'center'.",
        LoggerLevel.warning,
    )
    return Alignment.Center
}
