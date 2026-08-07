package com.abracode.actionui.Common

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.abracode.actionui.Helpers.ElementAnimator
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.dpProperty
import com.abracode.actionui.Helpers.floatProperty
import com.abracode.actionui.Helpers.numberProperty
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.resolveColorOrSemantic
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Translates an [ActionUIElement]'s `properties` JSON into a Compose [Modifier]
 * chain. Mirrors the role of `View.swift`'s shared modifier pipeline on the
 * Apple side - properties common to every element type are resolved once here
 * so individual element builders stay focused on their type-specific Composable.
 *
 * Compose has no inheritance equivalent to SwiftUI's `View` base class; instead,
 * universal modifiers chain on `Modifier.Companion` from any context, and a
 * second set is scope-restricted at compile time (e.g. `weight` only exists on
 * `RowScope`/`ColumnScope`, `align` is scope-specific). The resolver mirrors
 * that split:
 *
 *   * [applyCommonProperties] - extension on [Modifier], callable anywhere.
 *     Handles `zIndex`, `rotationEffect`, `scaleEffect`, `offset`, `frame`
 *     (SwiftUI sizing - fixed `{width,height}` or flexible `{minWidth,maxWidth,
 *     ...}` plus `alignment`), `opacity`, `hidden`, `shadow`, `border`,
 *     `clipShape`, `cornerRadius`, `background`, `padding`
 *     (number / EdgeInsets `{top,leading,bottom,trailing}` / `"default"`), and
 *     the four accessibility properties (`accessibilityLabel`,
 *     `accessibilityHint`, `accessibilityHidden`, `accessibilityIdentifier`)
 *     mapped to a single semantics block.
 *   * [buildChildModifier] - overloads on each layout scope receiver, applied
 *     inside the container's content lambda where `weight`/`align` are in
 *     scope. They resolve ONLY the scope-restricted parent data; the element's
 *     own common properties are applied by `BuildViewWithModifiers`
 *     (`Helpers/ViewModifierHelper.kt`), which needs
 *     the chain unfused so it can split it around a decoration `Box`.
 *
 * **Chain order** (universal). Modifiers earlier in the chain are outer for
 * layout, later are inner. Picked to make the most common combination behave
 * intuitively - a "card" with a background, rounded corners, and inner content
 * padding. The chain is split into two halves so the `overlay` / `background`
 * decoration subviews (`Helpers/ViewModifierHelper.kt`) can wrap a `Box`
 * between them - [applyOuterProperties] lands on the decoration `Box`,
 * [applyInnerProperties] on the element inside it, and [applyCommonProperties]
 * is simply their composition for the (overwhelmingly common) undecorated
 * element:
 *
 * ```
 *   outer:  accessibility semantics
 *          -> zIndex -> rotationEffect -> scaleEffect -> offset
 *          -> opacity -> hidden
 *   inner:  [padding, if a fixed frame follows] -> frame SIZING
 *          -> shadow -> border -> clipShape -> cornerRadius -> background
 *          -> frame CONTENT-ALIGNMENT (wrapContentSize) -> [padding, otherwise]
 * ```
 *
 * Frame is split: its SIZING (the width/height constraints) is OUTER so the
 * decoration (`background`/`border`/`clipShape`/`cornerRadius`) FILLS the framed
 * box, and its CONTENT ALIGNMENT (`wrapContentSize`, which positions a smaller
 * content within the box) is INNER, after the decoration. That is what keeps a
 * styled fixed/flex box filled when its content is empty or short, matching the
 * (reordered, frame-before-background) Apple pipeline and the Web single-node
 * renderer - the cross-platform FILLS contract (`Private/Layout_Engine_Parity.md`,
 * migration in `Private/Layout_Fill_Migration.md`).
 *
 * The cut sits between the whole-subtree wrappers and the element's own
 * size-and-decoration: a decoration subview must cover the element's
 * frame-plus-padding box (a `Capsule` background behind a padded `Text` covers
 * the padding - the SwiftUI badge idiom) and must move/fade with the carrier
 * (`offset`, `opacity` wrap the decorated unit). `clipShape`/`cornerRadius`
 * stay inner so a corner badge overlay is not clipped by the carrier's
 * rounding, as on Apple.
 *
 * Opacity (and `hidden`, which is `alpha(0)` plus an input block and an
 * accessibility hide - see [hiddenSubtree]) sit outside the decoration so they
 * fade the entire visual subtree including the background, not just inner
 * content; alpha is a draw-layer effect, so its position relative to the pure
 * layout modifiers (`frame`/`padding`) is visually inert - only its place
 * outside `shadow` matters (the shadow fades with the element). Padding is
 * innermost so the background fills the full size and the inner element sits
 * in a padded area inside the colored region - EXCEPT when a fixed frame is
 * present, where padding hoists outside the box (see the Sizing section in
 * [applyInnerProperties] for why). `border` is outside `clipShape` because
 * SwiftUI's `.border` is a rectangular stroke that is not clipped by a later
 * `.clipShape`.
 *
 * **Known divergences from SwiftUI** (Compose has no direct equivalent):
 *   * Compose constraints are hard caps, not SwiftUI's soft proposals a child
 *     may refuse: content larger than a fixed `frame` is capped to the box
 *     (SwiftUI lets it overflow at natural size). The two spots where this
 *     bites - padding inside the box and a missing default alignment - are
 *     handled (padding hoists outside a fixed frame; a fixed frame always
 *     `wrapContentSize`s its content, defaulting to center like Swift).
 *   * `shadow` maps to Compose's elevation shadow - `radius` becomes elevation
 *     and `color` becomes the ambient/spot color; the `x`/`y` offset is ignored.
 *   * `frame` `idealWidth`/`idealHeight` (SwiftUI's preferred size) is ignored
 *     with a warning - Compose has no preferred-size constraint, only min/max.
 *   * `clipShape` per-axis `cornerRadiusX`/`cornerRadiusY` (elliptical corners)
 *     is approximated with a single circular radius.
 *
 * Unknown values (e.g. `background: "not-a-color"`, `align: "wat"`) are skipped
 * and a warning is sent through the optional [logger]. Unrecognized property
 * names are ignored silently - they may be element-specific (e.g. `text` on
 * `Text`, `spacing` on `VStack`) and the element's own builder will pick them
 * up.
 *
 * [colorScheme] is the active `MaterialTheme.colorScheme`, captured at the
 * (composition) call site and passed down so color properties (`background`,
 * `shadow.color`, `border.color`) can resolve Apple **semantic** color names
 * (`secondary`, `fill.tertiary`, `tint`, ...) to adaptive Material roles via
 * [resolveColorOrSemantic]. `null` resolves literal colors only (the pure
 * `parseColor` vocabulary) - the pre-semantic behavior, kept for callers with no
 * theme in scope.
 */
fun Modifier.applyCommonProperties(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
    colorScheme: ColorScheme? = null
): Modifier =
    applyOuterProperties(properties, logger)
        .applyInnerProperties(properties, logger, colorScheme = colorScheme)

/**
 * The outer half of the common-property chain - the wrappers that act on the
 * whole decorated unit (see the chain-order section in the file header):
 * accessibility semantics, `zIndex`, `rotationEffect`, `scaleEffect`, `offset`,
 * `opacity`, and `hidden`. `BuildViewWithModifiers` puts this half on the decoration
 * `Box` when an element declares an `overlay`/`background` subview, so the
 * decorations move, fade, and stack with their carrier.
 */
fun Modifier.applyOuterProperties(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
    animator: ElementAnimator? = null
): Modifier {
    if (properties == null) return this
    var m: Modifier = this

    // ---- Accessibility semantics (outermost - Apple applies them last) ----
    m = m.applyAccessibility(properties, logger)

    // ---- Outer wrappers: draw ordering, transforms, position ----
    properties.numberProperty("zIndex")?.let { m = m.zIndex(it.toFloat()) }
    properties.numberProperty("rotationEffect")?.let {
        val degrees = it.toFloat()
        m = m.rotate(animator?.float("rotationEffect", degrees) ?: degrees)
    }
    m = m.applyScaleEffect(properties, animator)
    (properties["offset"] as? JsonObject)?.let { offset ->
        val x = (offset.numberProperty("x")?.toFloat() ?: 0f).dp
        val y = (offset.numberProperty("y")?.toFloat() ?: 0f).dp
        m = m.offset(
            x = animator?.dp("offset.x", x) ?: x,
            y = animator?.dp("offset.y", y) ?: y
        )
    }

    // ---- Opacity / visibility (outside decoration so the whole subtree fades) ----
    properties.floatProperty("opacity")?.let { m = m.alpha(animator?.float("opacity", it) ?: it) }
    if (properties.booleanProperty("hidden") == true) m = m.hiddenSubtree()
    return m
}

/**
 * `hidden: true`: invisible, NON-INTERACTIVE, and absent from the accessibility
 * tree - while still occupying its layout space, which is the behaviour Apple's
 * `.hidden()` defines and that authors write against.
 *
 * `alpha(0f)` alone was only the first of those three. A hidden element stayed
 * fully laid out AND fully hit-testable, so a hidden Button sitting over visible
 * content silently swallowed taps meant for what was underneath, and TalkBack
 * still announced controls that were not on screen. Apple's `.hidden()` and web's
 * `display: none` both take the view out of hit testing and out of accessibility,
 * so this was a real cross-platform divergence rather than a cosmetic one:
 * identical JSON behaved differently on Android in a way no author could see.
 *
 * Found by SharedCare brief 13, whose Activity section authors two hidden
 * interactive elements over visible content - a "Clear filters" Button centred in
 * the feed's own space, and a full-width "Show earlier" Button pinned across the
 * bottom of the section body, which overlaps the SCHEDULE body in the same
 * ZStack. Both intercepted taps meant for what was underneath. The out-of-scope
 * note on Missing_Features #34 had predicted exactly this.
 *
 * Input is blocked by consuming on the INITIAL pass, which is what keeps the event
 * from reaching descendants; a `clickable` on a child runs on the main pass and so
 * never sees it.
 */
private fun Modifier.hiddenSubtree(): Modifier = this
    .alpha(0f)
    .pointerInput(Unit) {
        awaitPointerEventScope {
            while (true) {
                awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
            }
        }
    }
    .semantics { hideFromAccessibility() }

/**
 * The inner half of the common-property chain - the element's own size and
 * decoration (see the chain-order section in the file header): `frame` and
 * `padding` (with the fixed-frame hoist), `shadow`, `border`, `clipShape`,
 * `cornerRadius`, and the `background` color. `BuildViewWithModifiers` puts this half on
 * the element inside the decoration `Box`, so an `overlay`/`background`
 * subview covers the frame-plus-padding box and is not clipped by the
 * carrier's `clipShape`/`cornerRadius`.
 */
fun Modifier.applyInnerProperties(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
    animator: ElementAnimator? = null,
    colorScheme: ColorScheme? = null
): Modifier {
    if (properties == null) return this
    var m: Modifier = this

    // ---- Sizing (OUTER, so the decoration below fills the framed box) ----
    // A fixed frame is a hard size in Compose - constraints are not SwiftUI's
    // soft proposals a child may refuse. Padding inside the box would subtract
    // from the content's max constraints and can crush a min-sized Material
    // component invisible (an M3 Button under `frame {height: 44} + padding 12`
    // gets 20dp and its title vanishes). So with a fixed frame, padding applies
    // OUTSIDE the box; the SwiftUI-visible result - content at its natural size
    // inside the frame - is preserved, at the cost of the padding reading as an
    // outer margin instead of SwiftUI's (center-invisible) inner inset.
    //
    // Only the SIZING goes here; the frame's content-alignment wrapContentSize is
    // applied AFTER the decoration (below), so `background`/`border`/`clip` fill
    // the framed size instead of hugging the (possibly empty/short) content - the
    // Android side of the cross-platform FILLS contract that the Apple pipeline
    // now shares (Private/Layout_Engine_Parity.md, Private/Layout_Fill_Migration.md).
    val frameObj = properties["frame"] as? JsonObject
    val hasFixedFrame = frameObj?.isFixedFrame() == true
    if (hasFixedFrame) m = m.applyPadding(properties)
    frameObj?.let { m = m.applyFrameSizing(it, logger, animator) }

    // ---- Decoration: shadow, border, clip, background - fills the framed box ----
    m = m.applyShadow(properties, colorScheme)
    m = m.applyBorder(properties, colorScheme)
    m = m.applyClipShape(properties, logger)
    properties.dpProperty("cornerRadius")?.let { m = m.clip(RoundedCornerShape(it)) }
    properties.stringProperty("background")?.let { name ->
        // Semantic names (e.g. "fill.tertiary", "background.secondary") resolve to
        // adaptive Material roles when a colorScheme is in scope; otherwise the
        // literal parseColor vocabulary. See resolveColorOrSemantic.
        val c = resolveColorOrSemantic(name, colorScheme)
        if (c != null) m = m.background(animator?.color("background", c) ?: c)
        else logger?.log(
            "Unknown color '$name' for property 'background'. Property ignored.",
            LoggerLevel.warning
        )
    }

    // ---- Frame content alignment (INNER: positions the content within the
    //      framed box, AFTER the decoration so the background filled the box) ----
    frameObj?.let { m = m.applyFrameContentAlignment(it, logger) }

    // ---- Padding (innermost, unless a fixed frame hoisted it - see Sizing) ----
    if (!hasFixedFrame) m = m.applyPadding(properties)
    return m
}

/**
 * Builds a Modifier for a child rendered inside a [androidx.compose.foundation.layout.Row].
 * Resolves `weight` (proportional sizing) and `align` (vertical positioning) -
 * the scope-restricted parent data only; the child's common properties are
 * applied by the `BuildViewWithModifiers` call it is passed to (see the file header).
 *
 * Recognized `align` values: `top`, `center` / `centerVertically`, `bottom`.
 */
fun RowScope.buildChildModifier(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    var m: Modifier = Modifier
    if (properties != null) {
        properties.floatProperty("weight")?.let { m = m.weight(it) }
        properties.stringProperty("align")?.let { name ->
            val a = parseVerticalAlignment(name)
            if (a != null) m = m.align(a)
            else logger?.log(
                "Unknown vertical alignment '$name' for Row child. Property ignored.",
                LoggerLevel.warning
            )
        }
    }
    return m
}

/**
 * Builds a Modifier for a child rendered inside a [androidx.compose.foundation.layout.Column].
 * Resolves `weight` and `align` (horizontal positioning) - the scope-restricted
 * parent data only; the child's common properties are applied by the
 * `BuildViewWithModifiers` call it is passed to (see the file header).
 *
 * Recognized `align` values: `start` / `leading`, `center` / `centerHorizontally`,
 * `end` / `trailing`.
 */
fun ColumnScope.buildChildModifier(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    var m: Modifier = Modifier
    if (properties != null) {
        properties.floatProperty("weight")?.let { m = m.weight(it) }
        properties.stringProperty("align")?.let { name ->
            val a = parseHorizontalAlignment(name)
            if (a != null) m = m.align(a)
            else logger?.log(
                "Unknown horizontal alignment '$name' for Column child. Property ignored.",
                LoggerLevel.warning
            )
        }
    }
    return m
}

/**
 * Builds a Modifier for a child rendered inside a [androidx.compose.foundation.layout.Box].
 * Resolves `align` (2D positioning) - the scope-restricted parent data only;
 * the child's common properties are applied by the `BuildViewWithModifiers`
 * call it is passed to (see the file header).
 *
 * Recognized `align` values: `topStart` / `topLeading`, `topCenter` / `top`,
 * `topEnd` / `topTrailing`, `centerStart` / `centerLeading`, `center`,
 * `centerEnd` / `centerTrailing`, `bottomStart` / `bottomLeading`,
 * `bottomCenter` / `bottom`, `bottomEnd` / `bottomTrailing`.
 */
fun BoxScope.buildChildModifier(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    var m: Modifier = Modifier
    if (properties != null) {
        properties.stringProperty("align")?.let { name ->
            val a = parseAlignment(name)
            if (a != null) m = m.align(a)
            else logger?.log(
                "Unknown alignment '$name' for Box child. Property ignored.",
                LoggerLevel.warning
            )
        }
    }
    return m
}

// ---------------------------------------------------------------------------
// Parsing helpers (internal so unit tests in the same package can reach them).
// Generic JSON accessors and color parsing live in `Helpers` (JsonProperty.kt,
// ColorHelper.kt); what stays here is the modifier-pipeline-specific parsing.
// ---------------------------------------------------------------------------

/**
 * Applies one axis of a SwiftUI `frame` to the Modifier. `frame` is ActionUI's
 * canonical, SwiftUI-named sizing property - `{ "width": N, "height": M }` -
 * mapped to `.frame(width:height:)` on Apple and to Compose `width`/`height`
 * here. There is deliberately no top-level `width`/`height` property; that is
 * not a SwiftUI modifier. The `"infinity"` sentinel fills the available axis.
 */
internal fun Modifier.applySizeAxis(
    value: JsonElement?,
    horizontal: Boolean,
    logger: ActionUILogger? = null,
    animator: ElementAnimator? = null
): Modifier {
    if (value == null) return this
    val prim = value.jsonPrimitive
    prim.doubleOrNull?.let { n ->
        val target = n.toFloat().dp
        val size = animator?.dp(if (horizontal) "frame.width" else "frame.height", target) ?: target
        return if (horizontal) this.width(size) else this.height(size)
    }
    if (prim.contentOrNull == "infinity") {
        return if (horizontal) this.fillMaxWidth() else this.fillMaxHeight()
    }
    logger?.log(
        "Unsupported frame.${if (horizontal) "width" else "height"} value " +
            "'${prim.contentOrNull}'. Expected a number or 'infinity'. Ignored.",
        LoggerLevel.warning
    )
    return this
}

/**
 * SwiftUI's `.padding()` with no argument uses a system-adaptive default
 * (roughly 16pt on iOS). Compose has no equivalent constant, so the `"default"`
 * string maps to this fixed approximation.
 */
private val DEFAULT_PADDING: Dp = 16.dp

/** A full-bounds oval, the Compose `Shape` analog of SwiftUI's `Ellipse`. */
private val EllipseShape: Shape = GenericShape { size, _ ->
    addOval(Rect(0f, 0f, size.width, size.height))
}

/**
 * The four universal accessibility properties, mapped to one semantics block
 * (`View.swift` applies them at the end of its pipeline, i.e. outermost - the
 * front of a Compose chain):
 *
 *   * `accessibilityLabel` -> `contentDescription` (TalkBack announces it in
 *     place of the node's own text, like VoiceOver with `.accessibilityLabel`).
 *   * `accessibilityHint` -> appended to the description after the label.
 *     TalkBack has no separate hint slot (VoiceOver reads the hint after a
 *     pause), so the hint joins the spoken description - a documented
 *     approximation, not a dropped property.
 *   * `accessibilityHidden: true` -> `hideFromAccessibility()`. `false` is a
 *     no-op, as on Apple.
 *   * `accessibilityIdentifier` -> the semantics `testTag`, Compose's UI-test
 *     handle (matched by `onNodeWithTag`), the same role the identifier plays
 *     for XCUITest.
 *
 * Types are validated warn-and-skip (`View.swift` parity). Elements whose icon
 * needs a glyph-level description and that render outside this pipeline
 * (toolbar chrome, tab items, menu items) keep their own `accessibilityLabel`
 * reads; elements rendered through it must NOT also set `contentDescription`
 * from the same property or TalkBack would announce the label twice
 * (`ContentDescription` semantics merge by list concatenation).
 */
private fun Modifier.applyAccessibility(
    properties: JsonObject,
    logger: ActionUILogger?
): Modifier {
    val label = properties.accessibilityString("accessibilityLabel", logger)
    val hint = properties.accessibilityString("accessibilityHint", logger)
    val identifier = properties.accessibilityString("accessibilityIdentifier", logger)
    val hidden = properties["accessibilityHidden"]?.let { raw ->
        val value = (raw as? JsonPrimitive)?.let { properties.booleanProperty("accessibilityHidden") }
        if (value == null) {
            logger?.log(
                "Invalid type for accessibilityHidden: expected Bool, ignoring",
                LoggerLevel.warning
            )
        }
        value
    } == true

    if (label == null && hint == null && identifier == null && !hidden) return this

    return this.semantics {
        val description = listOfNotNull(label, hint)
        if (description.isNotEmpty()) contentDescription = description.joinToString(". ")
        identifier?.let { testTag = it }
        if (hidden) hideFromAccessibility()
    }
}

/** A present-but-non-String accessibility property warns and reads as absent. */
private fun JsonObject.accessibilityString(key: String, logger: ActionUILogger?): String? {
    val raw = this[key] ?: return null
    if ((raw as? JsonPrimitive)?.isString != true) {
        logger?.log("Invalid type for $key: expected String, ignoring", LoggerLevel.warning)
        return null
    }
    return raw.content
}

/**
 * `scaleEffect` - uniform `Number` or `{ x, y, anchor }`. The uniform form uses
 * Compose's `scale` (center anchor); the dict form goes through `graphicsLayer`
 * so the `anchor` maps to a [TransformOrigin].
 */
private fun Modifier.applyScaleEffect(properties: JsonObject, animator: ElementAnimator? = null): Modifier {
    (properties["scaleEffect"] as? JsonObject)?.let { obj ->
        val sx = obj.numberProperty("x")?.toFloat() ?: 1f
        val sy = obj.numberProperty("y")?.toFloat() ?: 1f
        val animatedX = animator?.float("scaleEffect.x", sx) ?: sx
        val animatedY = animator?.float("scaleEffect.y", sy) ?: sy
        val origin = parseTransformOrigin(obj.stringProperty("anchor"))
        return this.graphicsLayer {
            scaleX = animatedX
            scaleY = animatedY
            transformOrigin = origin
        }
    }
    properties.numberProperty("scaleEffect")?.let {
        val s = it.toFloat()
        return this.scale(animator?.float("scaleEffect", s) ?: s)
    }
    return this
}

/** The flexible `frame` keys (min/ideal/max width/height). */
private val FLEX_FRAME_KEYS = listOf(
    "minWidth", "idealWidth", "maxWidth",
    "minHeight", "idealHeight", "maxHeight"
)

/** The fixed `frame` form: `{ width, height }` (either may be the `"infinity"` sentinel). */
private fun JsonObject.isFixedFrame(): Boolean = this["width"] != null || this["height"] != null

/** The flexible `frame` form: any of `min/ideal/max width/height`. */
private fun JsonObject.isFlexibleFrame(): Boolean = FLEX_FRAME_KEYS.any { this[it] != null }

/**
 * Frame SIZING - the width/height constraints ONLY, applied OUTER (before the
 * decoration) so `background`/`border`/`clip`/`cornerRadius` fill the framed
 * size. `frame` has two mutually exclusive forms:
 *   * Fixed: `{ width, height }` (each a number or the `"infinity"` sentinel).
 *   * Flexible: `{ minWidth, idealWidth, maxWidth, minHeight, idealHeight,
 *     maxHeight }` mapped to Compose `widthIn`/`heightIn` (ideal ignored - see
 *     the file header divergence note); `maxWidth/maxHeight: "infinity"` fills
 *     the axis, and a FINITE `maxWidth/maxHeight` grows the view UP TO the cap.
 *
 * The content-alignment `wrapContentSize` is applied separately, AFTER the
 * decoration, by [applyFrameContentAlignment]. Splitting sizing from alignment
 * is what lets a styled fixed/flex box keep its fill when its content is empty
 * or short, matching the reordered Apple pipeline (`View.swift`) and the Web
 * single-node renderer - see `Private/Layout_Engine_Parity.md`.
 */
private fun Modifier.applyFrameSizing(frame: JsonObject, logger: ActionUILogger?, animator: ElementAnimator? = null): Modifier {
    var m: Modifier = this
    if (frame.isFixedFrame()) {
        m = m.applySizeAxis(frame["width"], horizontal = true, logger, animator)
        m = m.applySizeAxis(frame["height"], horizontal = false, logger, animator)
    } else if (frame.isFlexibleFrame()) {
        m = m.applyFlexibleAxis(frame, horizontal = true, logger)
        m = m.applyFlexibleAxis(frame, horizontal = false, logger)
    }
    return m
}

/**
 * Frame CONTENT ALIGNMENT - the `wrapContentSize` that positions the (possibly
 * smaller) content WITHIN the framed box. Applied INNER, after the decoration,
 * so the background has already filled the box. A fixed frame ALWAYS wraps,
 * defaulting to center - Swift resolves a missing `alignment` to `.center`
 * (`View.swift`), and without the wrap the hard size would propagate INTO the
 * content and stretch/crush it, which SwiftUI's soft proposals never do.
 * (Content larger than the box is still capped - a Compose constraint,
 * divergence-noted in the header.) A flexible frame wraps only when `alignment`
 * is explicitly given.
 */
private fun Modifier.applyFrameContentAlignment(frame: JsonObject, logger: ActionUILogger?): Modifier {
    if (frame.isFixedFrame()) {
        val alignment = frame.stringProperty("alignment")
            ?.let { parseFrameAlignment(it, logger) } ?: Alignment.Center
        return this.wrapContentSize(alignment)
    } else if (frame.isFlexibleFrame()) {
        frame.stringProperty("alignment")?.let { name ->
            parseFrameAlignment(name, logger)?.let { return this.wrapContentSize(it) }
        }
    }
    return this
}

/** One axis of the flexible `frame` form - `min`/`max` to `widthIn`/`heightIn`. */
private fun Modifier.applyFlexibleAxis(
    frame: JsonObject,
    horizontal: Boolean,
    logger: ActionUILogger?
): Modifier {
    val minKey = if (horizontal) "minWidth" else "minHeight"
    val idealKey = if (horizontal) "idealWidth" else "idealHeight"
    val maxKey = if (horizontal) "maxWidth" else "maxHeight"

    if (frame[idealKey] != null) {
        logger?.log(
            "frame.$idealKey has no direct Compose equivalent (no preferred-size " +
                "constraint); ignored. Use min/max.",
            LoggerLevel.warning
        )
    }

    val minDp = frame.numberProperty(minKey)?.toFloat()?.dp
    val maxPrim = frame[maxKey]?.jsonPrimitive
    val maxInfinity = maxPrim?.contentOrNull == "infinity"
    val maxDp = maxPrim?.doubleOrNull?.toFloat()?.dp

    var m: Modifier = this
    if (minDp != null || maxDp != null) {
        m = if (horizontal) {
            m.widthIn(min = minDp ?: Dp.Unspecified, max = maxDp ?: Dp.Unspecified)
        } else {
            m.heightIn(min = minDp ?: Dp.Unspecified, max = maxDp ?: Dp.Unspecified)
        }
    }
    // A present max GROWS the view to fill UP TO that bound: "infinity" fills the
    // axis, and a FINITE cap fills up to the cap (bounded by the widthIn/heightIn
    // above, so fillMax resolves to min(parent, cap)). This matches SwiftUI
    // `.frame(maxWidth:)`, which grows to its cap - a bare `widthIn` only bounds
    // and leaves the view content-sized (the Issue B divergence). A min-only frame
    // does NOT grow (SwiftUI keeps it content-sized above the floor), so the fill
    // is gated on a max being present. As a stack MAIN-axis child the custom stack
    // layout (StackLayout.kt) sizes the slot and this fill just fills it.
    if (maxInfinity || maxDp != null) {
        m = if (horizontal) m.fillMaxWidth() else m.fillMaxHeight()
    }
    return m
}

/**
 * `shadow` - `{ color, radius, x, y }`. Maps to Compose's elevation shadow:
 * `radius` -> elevation, `color` -> ambient/spot color. The `x`/`y` offset has
 * no elevation-shadow equivalent and is ignored (see file header divergences).
 */
private fun Modifier.applyShadow(properties: JsonObject, colorScheme: ColorScheme? = null): Modifier {
    val shadow = properties["shadow"] as? JsonObject ?: return this
    val radius = (shadow.numberProperty("radius") ?: 0.0).toFloat()
    val color = shadow.stringProperty("color")?.let { resolveColorOrSemantic(it, colorScheme) } ?: Color.Black
    return this.shadow(
        elevation = radius.dp,
        shape = RectangleShape,
        clip = false,
        ambientColor = color,
        spotColor = color
    )
}

/**
 * `border` - `{ color, width }`. SwiftUI's `.border` is a rectangular stroke, so
 * the Compose mapping uses [RectangleShape] regardless of any `clipShape`.
 */
private fun Modifier.applyBorder(properties: JsonObject, colorScheme: ColorScheme? = null): Modifier {
    val border = properties["border"] as? JsonObject ?: return this
    val color = border.stringProperty("color")?.let { resolveColorOrSemantic(it, colorScheme) } ?: Color.Black
    val width = (border.numberProperty("width") ?: 1.0).toFloat()
    return this.border(width.dp, color, RectangleShape)
}

/** `clipShape` - named shape string or a `{ type: "roundedRectangle", ... }` dict. */
private fun Modifier.applyClipShape(properties: JsonObject, logger: ActionUILogger?): Modifier {
    val element = properties["clipShape"] ?: return this
    val shape = parseClipShape(element, logger) ?: return this
    return this.clip(shape)
}

/** `padding` - uniform `Number`, EdgeInsets `{top,leading,bottom,trailing}`, or `"default"`. */
private fun Modifier.applyPadding(properties: JsonObject): Modifier {
    (properties["padding"] as? JsonObject)?.let { insets ->
        return this.padding(
            start = (insets.numberProperty("leading") ?: 0.0).toFloat().dp,
            top = (insets.numberProperty("top") ?: 0.0).toFloat().dp,
            end = (insets.numberProperty("trailing") ?: 0.0).toFloat().dp,
            bottom = (insets.numberProperty("bottom") ?: 0.0).toFloat().dp
        )
    }
    properties.dpProperty("padding")?.let { return this.padding(it) }
    if (properties.stringProperty("padding")?.lowercase() == "default") {
        return this.padding(DEFAULT_PADDING)
    }
    return this
}

/**
 * Resolves a SwiftUI `frame` alignment name into a Compose 2D [Alignment].
 * SwiftUI's edge names (`leading`/`trailing`/`top`/`bottom`) center on the other
 * axis, matching `.frame(alignment:)` semantics.
 */
internal fun parseFrameAlignment(name: String, logger: ActionUILogger? = null): Alignment? =
    when (name) {
        "leading"        -> Alignment.CenterStart
        "trailing"       -> Alignment.CenterEnd
        "top"            -> Alignment.TopCenter
        "bottom"         -> Alignment.BottomCenter
        "center"         -> Alignment.Center
        "topLeading"     -> Alignment.TopStart
        "topTrailing"    -> Alignment.TopEnd
        "bottomLeading"  -> Alignment.BottomStart
        "bottomTrailing" -> Alignment.BottomEnd
        else -> {
            logger?.log(
                "Unknown frame alignment '$name'. Property ignored.",
                LoggerLevel.warning
            )
            null
        }
    }

/**
 * Resolves a `clipShape` value into a Compose [Shape]. String form accepts
 * `circle`/`capsule`/`ellipse`/`rectangle`; dict form accepts
 * `{ type: "roundedRectangle", cornerRadius }` or per-axis
 * `cornerRadiusX`/`cornerRadiusY` (approximated - see file header divergences).
 * Returns `null` (with a warning) for unrecognized input.
 */
internal fun parseClipShape(element: JsonElement, logger: ActionUILogger? = null): Shape? {
    (element as? JsonPrimitive)?.let { prim ->
        if (prim.isString) {
            return when (prim.content.lowercase()) {
                "circle"    -> CircleShape
                "capsule"   -> RoundedCornerShape(percent = 50)
                "ellipse"   -> EllipseShape
                "rectangle" -> RectangleShape
                else -> {
                    logger?.log(
                        "Unknown clipShape '${prim.content}'. Property ignored.",
                        LoggerLevel.warning
                    )
                    null
                }
            }
        }
    }
    (element as? JsonObject)?.let { obj ->
        if (obj.stringProperty("type") == "roundedRectangle") {
            obj.numberProperty("cornerRadius")?.let {
                return RoundedCornerShape(it.toFloat().dp)
            }
            val rx = obj.numberProperty("cornerRadiusX")
            val ry = obj.numberProperty("cornerRadiusY")
            if (rx != null && ry != null) {
                logger?.log(
                    "clipShape per-axis cornerRadiusX/cornerRadiusY (elliptical " +
                        "corners) is approximated with a single radius on Android.",
                    LoggerLevel.warning
                )
                return RoundedCornerShape(rx.toFloat().dp)
            }
        }
        logger?.log("Unsupported clipShape object. Property ignored.", LoggerLevel.warning)
        return null
    }
    return null
}

/** Maps a SwiftUI `scaleEffect` anchor name to a Compose [TransformOrigin]; defaults to center. */
internal fun parseTransformOrigin(name: String?): TransformOrigin =
    when (name) {
        "leading"        -> TransformOrigin(0f, 0.5f)
        "trailing"       -> TransformOrigin(1f, 0.5f)
        "top"            -> TransformOrigin(0.5f, 0f)
        "bottom"         -> TransformOrigin(0.5f, 1f)
        "topLeading"     -> TransformOrigin(0f, 0f)
        "topTrailing"    -> TransformOrigin(1f, 0f)
        "bottomLeading"  -> TransformOrigin(0f, 1f)
        "bottomTrailing" -> TransformOrigin(1f, 1f)
        else             -> TransformOrigin.Center
    }

internal fun parseVerticalAlignment(name: String): Alignment.Vertical? =
    when (name.lowercase()) {
        "top"                          -> Alignment.Top
        "center", "centervertically"   -> Alignment.CenterVertically
        "bottom"                       -> Alignment.Bottom
        else                           -> null
    }

internal fun parseHorizontalAlignment(name: String): Alignment.Horizontal? =
    when (name.lowercase()) {
        "start", "leading"              -> Alignment.Start
        "center", "centerhorizontally"  -> Alignment.CenterHorizontally
        "end", "trailing"               -> Alignment.End
        else                            -> null
    }

/**
 * Resolves a Row/HStack parent-level alignment name into the Compose value.
 * Accepts SwiftUI vocabulary so a single JSON file works on both platforms:
 *
 *   * `top`                                    -> [Alignment.Top]
 *   * `center` / `centerVertically`            -> [Alignment.CenterVertically]
 *   * `bottom`                                 -> [Alignment.Bottom]
 *   * `firstTextBaseline` / `lastTextBaseline` -> `null` (no direct Compose
 *     equivalent) + warning through [logger]. The caller's default alignment
 *     applies - matches "ignore unrecognized" semantics and avoids visually
 *     misleading the reader with an artificial Top fallback that doesn't
 *     reflect the SwiftUI intent.
 *
 * Returns `null` for unknown or unsupported names; the call site picks a
 * default and the warning is emitted here.
 *
 * See `Private/Android_Porting_Notes.md` for the deferred decision around
 * mapping baseline alignment to Compose's per-child `alignByBaseline()`.
 */
internal fun parseRowAlignment(
    name: String,
    logger: ActionUILogger? = null
): Alignment.Vertical? {
    parseVerticalAlignment(name)?.let { return it }
    if (isBaselineAlignmentName(name)) {
        logger?.log(
            "Row/HStack alignment '$name' has no direct Compose equivalent; " +
                "default alignment will be used. (SwiftUI baseline alignment " +
                "is Compose-incompatible at the parent level.)",
            LoggerLevel.warning
        )
        return null
    }
    logger?.log(
        "Unknown alignment '$name' for Row/HStack. Falling back to default.",
        LoggerLevel.warning
    )
    return null
}

/**
 * Resolves a Column/VStack parent-level alignment name. SwiftUI's
 * `HorizontalAlignment` only has `.leading` / `.center` / `.trailing` -
 * no baseline variants - so this is a thin wrapper that adds logging on
 * unknown values.
 *
 * Accepts: `start` / `leading`, `center` / `centerHorizontally`,
 * `end` / `trailing`.
 */
internal fun parseColumnAlignment(
    name: String,
    logger: ActionUILogger? = null
): Alignment.Horizontal? {
    parseHorizontalAlignment(name)?.let { return it }
    logger?.log(
        "Unknown alignment '$name' for Column/VStack. Falling back to default.",
        LoggerLevel.warning
    )
    return null
}

private fun isBaselineAlignmentName(name: String): Boolean =
    name.lowercase() in setOf("firsttextbaseline", "lasttextbaseline")

internal fun parseAlignment(name: String): Alignment? =
    when (name.lowercase()) {
        "topstart", "topleading"                   -> Alignment.TopStart
        "topcenter", "top"                         -> Alignment.TopCenter
        "topend", "toptrailing"                    -> Alignment.TopEnd
        // SwiftUI's plain `.leading`/`.trailing` are vertically centered.
        "centerstart", "centerleading", "leading"  -> Alignment.CenterStart
        "center"                                   -> Alignment.Center
        "centerend", "centertrailing", "trailing"  -> Alignment.CenterEnd
        "bottomstart", "bottomleading"             -> Alignment.BottomStart
        "bottomcenter", "bottom"                   -> Alignment.BottomCenter
        "bottomend", "bottomtrailing"              -> Alignment.BottomEnd
        else                                       -> null
    }
