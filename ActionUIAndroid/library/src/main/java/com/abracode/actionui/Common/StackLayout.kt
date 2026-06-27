package com.abracode.actionui.Common

import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Measurable
import androidx.compose.ui.layout.MeasurePolicy
import androidx.compose.ui.layout.ParentDataModifier
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * The custom Compose layout that backs [com.abracode.actionui.Views.HStack] and
 * [com.abracode.actionui.Views.VStack], replacing Compose's `Row`/`Column` so
 * the stacks reproduce SwiftUI's distribution instead of Compose's.
 *
 * ## Why not `Row`/`Column`
 *
 * Compose's `Row` measures children against the available space in a way that
 * lets an intrinsically GREEDY child (a Material `TextField`, which fills its
 * width) take 100% and STARVE its inflexible siblings - a compact `Picker` next
 * to it collapses. SwiftUI's HStack (and CSS flexbox) instead give inflexible
 * children their size first and let the flexible ones divide what's left. The
 * layout probe (2026-06-24) confirmed Apple/Web reserve siblings and Compose did
 * not; this layout closes that gap. The space split itself is the pure, unit-
 * tested [distributeMainAxis] (`StackDistribution.kt`).
 *
 * ## How a child's flexibility is determined (no intrinsics, single measure)
 *
 * Querying Compose intrinsics is fragile (some composables throw), and Compose
 * forbids measuring a child twice in one pass. So:
 *   * A FLEXIBLE child declares itself via [StackChildData] (attached by the stack
 *     via [stackChild] from its `frame`/type): `fill` (`maxWidth: infinity`, a
 *     `Spacer`, a `weight`, or a greedy text input - [GREEDY_LEAF_TYPES]). These
 *     are NOT pre-measured; they are measured once, later, with the remainder.
 *   * Every other child (fixed size, or content) is measured ONCE up front to its
 *     natural size and reserved.
 *
 * Reserved children take their space first; the flexible ones split what is left
 * via [distributeMainAxis]; each child is measured exactly once. The cross axis
 * stays flexible (a child's own `frame` `maxHeight: infinity` still fills it via
 * its modifier).
 *
 * Known iteration-1 limits (revisit with screenshots): an unbounded MAIN axis (an
 * HStack inside a horizontal scroller) uses a coarse greedy fallback; per-child
 * `align` and proportional `weight` ratios are not yet honored (a `weight` reads
 * as a plain fill). These do not affect the converter / probe.
 */

/**
 * Per-child main-axis sizing the stack derives from the child's `frame`/type and
 * the [stackMeasurePolicy] reads back. dp values are kept raw and converted to
 * px inside the policy (which is a [Density]).
 */
class StackChildData(
    val fixedMainDp: Float? = null,
    val minMainDp: Float? = null,
    val fill: Boolean = false,
    // Fill the CROSS axis (not the main axis): a width-greedy text leaf in a VStack
    // stretches to the stack's width while hugging its (main-axis) height.
    val crossFill: Boolean = false,
)

private class StackChildDataModifier(val data: StackChildData) : ParentDataModifier {
    override fun Density.modifyParentData(parentData: Any?): Any = data
}

/** Attaches [data] as parent data so [stackMeasurePolicy] can classify the child. */
fun Modifier.stackChild(data: StackChildData): Modifier = this.then(StackChildDataModifier(data))

/**
 * The greedy text-input element types. A TextField/SecureField is greedy on the WIDTH
 * axis only (fixed height, as on Apple): it fills an HStack's main axis, but in a VStack
 * it fills the CROSS axis (width) and hugs its height - it must NOT fill the vertical main
 * axis (that ballooned the field). A TextEditor is multi-line and greedy on BOTH axes, so
 * it stays main-greedy in either orientation. See stackChildDataFor.
 */
private val GREEDY_LEAF_TYPES = setOf("TextField", "SecureField", "TextEditor")

/**
 * Builds the [StackChildData] for [element] in a stack of the given axis, by
 * reading its `frame` (the main-axis keys for that axis) and its type. A child is
 * `fill` (flexible) when its main axis is `infinity`, when it declares an
 * `idealWidth`/`idealHeight` with no fixed/max cap (SwiftUI treats an ideal-only
 * frame as flexible - a greedy control ignores its ideal), when it is a `Spacer`,
 * when it declares a `weight`, or when it is a greedy text input with no cap.
 */
internal fun stackChildDataFor(element: ActionUIElement, horizontal: Boolean): StackChildData {
    val props = element.properties
    val frame = props?.get("frame") as? JsonObject
    val fixedKey = if (horizontal) "width" else "height"
    val minKey = if (horizontal) "minWidth" else "minHeight"
    val maxKey = if (horizontal) "maxWidth" else "maxHeight"

    fun num(key: String): Float? = (frame?.get(key) as? JsonPrimitive)?.doubleOrNull?.toFloat()
    fun isInfinity(key: String): Boolean = (frame?.get(key) as? JsonPrimitive)?.contentOrNull == "infinity"

    val fixed = num(fixedKey)
    val maxFinite = num(maxKey)
    val greedyLeaf = element.type in GREEDY_LEAF_TYPES
    // A TextField/SecureField is greedy on the WIDTH axis only, so it fills the MAIN
    // axis only in a horizontal stack; in a VStack it hugs its height (handled as
    // crossFill below). A TextEditor is multi-line and fills the main axis in either
    // orientation.
    val mainGreedy = greedyLeaf && (horizontal || element.type == "TextEditor")

    // `idealWidth`/`idealHeight` does NOT itself make a child greedy: SwiftUI uses
    // the ideal only when the parent's proposal is unspecified (rare in a stack),
    // so in a stack it is a near-no-op and the child's own nature decides - a
    // greedy control (TextField) fills, a Text stays content-sized. The empirical
    // pre-measure in stackMeasurePolicy catches greedy leaves with no `frame`; the
    // GREEDY_LEAF_TYPES set covers them when a (non-cap) `frame` is also present.
    val fill = isInfinity(fixedKey) || isInfinity(maxKey) ||
        element.type == "Spacer" ||
        props?.get("weight") != null ||
        (mainGreedy && fixed == null && maxFinite == null)

    // A width-greedy text leaf (TextField/SecureField) in a VStack fills the CROSS
    // axis (width) when it has no explicit cross-axis frame - the SwiftUI default
    // where a TextField stretches to the stack's width while keeping its own height.
    // An explicit width/maxWidth frame (incl. maxWidth:infinity, which ModifierResolver
    // turns into fillMaxWidth) governs the cross axis instead, so skip crossFill then.
    val crossKeys = if (horizontal) listOf("height", "maxHeight", "minHeight")
                    else listOf("width", "maxWidth", "minWidth")
    val hasCrossFrame = crossKeys.any { frame?.get(it) != null }
    val crossFill = greedyLeaf && !fill && !horizontal && !hasCrossFrame

    return StackChildData(
        fixedMainDp = if (fill) null else fixed,
        minMainDp = num(minKey),
        fill = fill,
        crossFill = crossFill,
    )
}

/**
 * A [MeasurePolicy] implementing SwiftUI's main-axis distribution for an
 * HStack ([horizontal] = true; cross = vertical, positioned by
 * [verticalAlignment]) or a VStack ([horizontal] = false; cross = horizontal,
 * positioned by [horizontalAlignment]). See the file header.
 */
internal fun stackMeasurePolicy(
    horizontal: Boolean,
    spacing: Dp,
    verticalAlignment: Alignment.Vertical?,
    horizontalAlignment: Alignment.Horizontal?,
): MeasurePolicy = MeasurePolicy { measurables, constraints ->
    val n = measurables.size
    if (n == 0) {
        return@MeasurePolicy layout(constraints.minWidth, constraints.minHeight) {}
    }

    val spacingPx = spacing.roundToPx()
    val totalSpacing = if (n > 1) spacingPx * (n - 1) else 0
    val mainMax = if (horizontal) constraints.maxWidth else constraints.maxHeight
    val crossMax = if (horizontal) constraints.maxHeight else constraints.maxWidth
    val mainBounded = mainMax != Constraints.Infinity
    // Loose upper bound for pre-measuring a non-greedy child to its natural size;
    // in an unbounded main axis fall back to a generous fixed extent (a child
    // cannot be measured against an infinite main-axis constraint).
    val looseMainMax = if (mainBounded) mainMax else 100_000

    fun crossConstraints(mainSize: Int): Constraints =
        if (horizontal) Constraints(minWidth = mainSize, maxWidth = mainSize, minHeight = 0, maxHeight = crossMax)
        else Constraints(minWidth = 0, maxWidth = crossMax, minHeight = mainSize, maxHeight = mainSize)

    fun looseConstraints(minMain: Int): Constraints =
        if (horizontal) Constraints(minWidth = minMain, maxWidth = looseMainMax, minHeight = 0, maxHeight = crossMax)
        else Constraints(minWidth = 0, maxWidth = crossMax, minHeight = minMain, maxHeight = looseMainMax)

    // Like looseConstraints, but PINS the cross axis to crossMax - used for a
    // width-greedy text leaf (crossFill) so it stretches to the stack's width while
    // still hugging its main-axis height. Only valid when crossMax is bounded.
    fun crossFillConstraints(minMain: Int): Constraints =
        if (horizontal) Constraints(minWidth = minMain, maxWidth = looseMainMax, minHeight = crossMax, maxHeight = crossMax)
        else Constraints(minWidth = crossMax, maxWidth = crossMax, minHeight = minMain, maxHeight = looseMainMax)

    fun Placeable.mainSize() = if (horizontal) width else height
    fun Placeable.crossSize() = if (horizontal) height else width

    val placeables = arrayOfNulls<Placeable>(n)
    val sizings = ArrayList<StackChildSizing>(n)

    for (i in 0 until n) {
        val m = measurables[i]
        val d = m.parentData as? StackChildData
        val fixedMain = d?.fixedMainDp?.let { it.dp.roundToPx() }
        val minMain = d?.minMainDp?.let { it.dp.roundToPx() } ?: 0
        when {
            d?.fill == true -> {
                // Greedy: it will take the remainder. Measured after distribution.
                sizings.add(StackChildSizing.of(minMain, minMain, UNBOUNDED))
            }
            fixedMain != null -> {
                placeables[i] = m.measure(crossConstraints(fixedMain))
                sizings.add(StackChildSizing.of(fixedMain, fixedMain, fixedMain))
            }
            else -> {
                // A non-greedy child: measure ONCE to its natural size and reserve
                // it. Compose forbids measuring a child twice in a pass, so greedy
                // children must declare themselves (frame fill / GREEDY_LEAF_TYPES /
                // Spacer / weight) and are sized in the second pass below; we do NOT
                // re-measure here on a guessed greed. A crossFill text leaf (e.g. a
                // TextField in a VStack) is pinned to the stack width on the cross axis.
                val cons = if (d?.crossFill == true && crossMax != Constraints.Infinity)
                    crossFillConstraints(minMain) else looseConstraints(minMain)
                val p = m.measure(cons)
                placeables[i] = p
                val natural = p.mainSize()
                sizings.add(StackChildSizing.of(natural, natural, natural))
            }
        }
    }

    val mains = if (mainBounded) {
        distributeMainAxis(sizings, mainMax, totalSpacing)
    } else {
        IntArray(n) { sizings[it].ideal }
    }

    // Greedy (fill) children were not pre-measured; measure each EXACTLY ONCE now
    // with the remainder the distribution handed it. Already-measured children keep
    // their single measurement (a reserved child's size is its natural size).
    for (i in 0 until n) {
        if (placeables[i] == null) {
            placeables[i] = measurables[i].measure(crossConstraints(mains[i]))
        }
    }

    var mainTotal = totalSpacing
    var crossTotal = 0
    for (i in 0 until n) {
        mainTotal += placeables[i]!!.mainSize()
        crossTotal = maxOf(crossTotal, placeables[i]!!.crossSize())
    }

    val width = if (horizontal) mainTotal else crossTotal
    val height = if (horizontal) crossTotal else mainTotal
    // Clamp into the incoming constraints. The upper bound is raised to at least
    // minWidth/minHeight so the coerce range can never be empty (coerceIn throws
    // on an empty range - e.g. an unbounded axis whose content is below the min).
    val maxOutW = maxOf(constraints.minWidth, if (constraints.hasBoundedWidth) constraints.maxWidth else width)
    val maxOutH = maxOf(constraints.minHeight, if (constraints.hasBoundedHeight) constraints.maxHeight else height)
    val outW = width.coerceIn(constraints.minWidth, maxOutW)
    val outH = height.coerceIn(constraints.minHeight, maxOutH)

    layout(outW, outH) {
        var pos = 0
        for (i in 0 until n) {
            val p = placeables[i]!!
            val crossOffset = if (horizontal) {
                (verticalAlignment ?: Alignment.CenterVertically).align(p.crossSize(), outH)
            } else {
                (horizontalAlignment ?: Alignment.Start).align(p.crossSize(), outW, layoutDirection)
            }
            if (horizontal) p.placeRelative(pos, crossOffset) else p.placeRelative(crossOffset, pos)
            pos += p.mainSize() + spacingPx
        }
    }
}
