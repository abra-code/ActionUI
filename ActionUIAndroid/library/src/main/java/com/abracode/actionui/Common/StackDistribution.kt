package com.abracode.actionui.Common

/**
 * SwiftUI's HStack/VStack MAIN-AXIS space distribution, as a pure (Compose-free)
 * function so the algorithm can be unit-tested directly. The custom stack
 * `Layout` (see `StackLayout.kt`) collects each child's sizing from intrinsics
 * and/or its `frame`, calls [distributeMainAxis], then measures and places.
 *
 * ## Why this exists
 *
 * Compose's `Row`/`Column` measure children roughly in order against the
 * available space, so an intrinsically GREEDY child (a Material `TextField`,
 * which fills its width) takes 100% and starves its inflexible siblings - a
 * compact `Picker` next to it collapses. SwiftUI's HStack and CSS flexbox do
 * NOT do this: they give inflexible children their size FIRST and let the
 * flexible ones divide what's left. This function reproduces SwiftUI's rule so
 * Android matches Apple/Web (the sibling-starvation divergence found by the
 * layout probe, 2026-06-24).
 *
 * ## The algorithm (SwiftUI, same layout priority)
 *
 * Process children in order of INCREASING flexibility (least flexible first).
 * To each, propose `remainingSpace / remainingChildCount`; the child takes that
 * proposal CLAMPED to its own `[min, max]` range; subtract and continue. Because
 * rigid children (fixed width, content-sized text) come first and accept only
 * their small size, the pool they leave behind flows to the flexible children at
 * the end, which split it. A fully greedy child ([max] == [UNBOUNDED]) accepts
 * whatever proposal it gets. Integer division truncates; the leftover lands on
 * the last (most flexible) child, whose proposal is the entire remaining pool.
 *
 * Worked examples (available = 300, no spacing):
 *   * `[TextField(greedy), Picker(content 50)]` -> Picker (flex 0) first: takes
 *     50; TextField gets 250. The reservation that fixes the bug.
 *   * `[box(maxWidth:inf), box(maxWidth:inf)]` -> 150 / 150 (equal split).
 *   * `[width 90, box(maxWidth:inf)]` -> 90 / 210.
 *
 * This function assumes a BOUNDED main axis. An unbounded main axis (an HStack
 * inside a horizontal scroller) is handled by the caller, which sizes every
 * child to its ideal instead of distributing.
 */

/** Sentinel main-axis upper bound for a fully greedy child (`maxWidth: infinity`, a Spacer, a greedy control). */
const val UNBOUNDED: Int = Int.MAX_VALUE

/**
 * One child's main-axis sizing inputs. Built by the stack from the child's
 * `frame` (when present) or its Compose intrinsics (otherwise):
 *
 * @param min the smallest main-axis size the child accepts (minIntrinsic, or `frame.minWidth`, or a fixed size).
 * @param ideal the child's preferred/content main-axis size (maxIntrinsic, or a fixed/ideal frame size); also the upper bound for a rigid child.
 * @param max the largest main-axis size the child accepts: [ideal] for a rigid child, a finite cap for `maxWidth: N`, or [UNBOUNDED] for a greedy child.
 *
 * Values are coerced into a consistent order (`0 <= min <= ideal <= max`) so a
 * stray intrinsic can never make distribution throw mid-layout.
 */
class StackChildSizing private constructor(val min: Int, val ideal: Int, val max: Int) {
    /** SwiftUI's ordering metric: how much the child can grow above its minimum. */
    val flexibility: Long get() = max.toLong() - min.toLong()

    companion object {
        fun of(min: Int, ideal: Int, max: Int): StackChildSizing {
            val lo = min.coerceAtLeast(0)
            val id = ideal.coerceAtLeast(lo)
            val hi = max.coerceAtLeast(id)
            return StackChildSizing(lo, id, hi)
        }
    }

    override fun toString(): String =
        "StackChildSizing(min=$min, ideal=$ideal, max=${if (max == UNBOUNDED) "UNBOUNDED" else max})"
}

/**
 * Distributes [available] main-axis space (already net of nothing - [totalSpacing]
 * is subtracted here) across [children], returning each child's allotted size in
 * the INPUT order. See the file header for the algorithm.
 */
fun distributeMainAxis(children: List<StackChildSizing>, available: Int, totalSpacing: Int): IntArray {
    val n = children.size
    val result = IntArray(n)
    if (n == 0) return result

    // The pool to divide. May be negative if the children's minimums already
    // overflow the stack; clamping each child to its own min below then lets the
    // content overflow (a Compose hard-constraint reality, as on a tight Row).
    var remaining = available - totalSpacing

    // Least-flexible first. A stable sort keeps input order among equal-flex
    // children, so two `maxWidth:infinity` siblings split deterministically.
    val order = (0 until n).sortedBy { children[it].flexibility }

    var remainingCount = n
    for (idx in order) {
        val c = children[idx]
        val proposal = if (remainingCount > 0) remaining / remainingCount else 0
        val w = proposal.coerceIn(c.min, c.max)
        result[idx] = w
        remaining -= w
        remainingCount -= 1
    }
    return result
}
