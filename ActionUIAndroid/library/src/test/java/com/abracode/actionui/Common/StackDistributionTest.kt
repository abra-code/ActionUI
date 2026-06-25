package com.abracode.actionui.Common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [distributeMainAxis] - the pure core of the custom stack layout
 * that reproduces SwiftUI's HStack/VStack distribution. Each case encodes a
 * SwiftUI expectation; the layout probe (2026-06-24) confirmed Apple is the
 * reference and Compose's `Row` diverged on sibling reservation, which these
 * pin so the custom layout cannot regress it.
 *
 * Sizing shorthands for readability:
 */
class StackDistributionTest {

    private fun rigid(size: Int) = StackChildSizing.of(size, size, size)               // fixed width:N / content
    private fun content(min: Int, ideal: Int) = StackChildSizing.of(min, ideal, ideal)  // a Text: shrinks to min, no growth past content
    private fun greedy(min: Int = 0) = StackChildSizing.of(min, min, UNBOUNDED)          // TextField / maxWidth:infinity / Spacer
    private fun capped(min: Int, max: Int) = StackChildSizing.of(min, min, max)          // maxWidth:N

    // --- THE bug fix: a greedy child must NOT starve an inflexible sibling ---

    @Test
    fun `greedy field reserves space for a compact picker sibling`() {
        // [TextField(greedy), Picker(content 50)] in 300: the picker (flex 0) is
        // sized first to 50, the field takes the remaining 250 - NOT 300/0 (the
        // Compose Row starvation the probe caught on Android).
        val out = distributeMainAxis(listOf(greedy(), rigid(50)), available = 300, totalSpacing = 0)
        assertEquals(250, out[0])
        assertEquals(50, out[1])
    }

    @Test
    fun `order does not matter - picker first or field first reserves the same`() {
        val fieldFirst = distributeMainAxis(listOf(greedy(), rigid(50)), 300, 0)
        val pickerFirst = distributeMainAxis(listOf(rigid(50), greedy()), 300, 0)
        assertEquals(250, fieldFirst[0]); assertEquals(50, fieldFirst[1])
        assertEquals(50, pickerFirst[0]); assertEquals(250, pickerFirst[1])
    }

    // --- The probe cases B/C/D (which already matched) stay correct ---

    @Test
    fun `two maxWidth-infinity children split equally (probe C)`() {
        val out = distributeMainAxis(listOf(greedy(), greedy()), available = 300, totalSpacing = 0)
        assertEquals(150, out[0])
        assertEquals(150, out[1])
    }

    @Test
    fun `fixed width plus a flexible child - fixed takes its size, flex takes the rest (probe D)`() {
        val out = distributeMainAxis(listOf(rigid(90), greedy()), available = 300, totalSpacing = 0)
        assertEquals(90, out[0])
        assertEquals(210, out[1])
    }

    @Test
    fun `a finite maxWidth grows to its cap but no further (probe B grow-to-cap)`() {
        // capped(100, 260) next to a greedy sibling in plenty of space: it grows
        // to its 260 cap; the greedy child takes the rest.
        val out = distributeMainAxis(listOf(capped(100, 260), greedy()), available = 600, totalSpacing = 0)
        assertEquals(260, out[0])
        assertEquals(340, out[1])
    }

    @Test
    fun `three greedy children split into thirds with the rounding remainder on the last`() {
        val out = distributeMainAxis(listOf(greedy(), greedy(), greedy()), available = 301, totalSpacing = 0)
        // 301/3 = 100 (trunc) to the first two; the last gets the remaining 101.
        assertEquals(100, out[0])
        assertEquals(100, out[1])
        assertEquals(101, out[2])
        assertEquals(301, out.sum())
    }

    // --- Reservation with several inflexible children ---

    @Test
    fun `multiple rigid children are all reserved before the flexible one`() {
        // [width 90, content(50..120), TextField] in 400.
        val out = distributeMainAxis(listOf(rigid(90), content(50, 120), greedy()), available = 400, totalSpacing = 0)
        assertEquals(90, out[0])
        // content child: proposal (400-90)/2 = 155 >= its 120 ideal, so it takes 120.
        assertEquals(120, out[1])
        assertEquals(190, out[2])
        assertEquals(400, out.sum())
    }

    @Test
    fun `a content child squeezed below its ideal wraps to the proposal, not its content`() {
        // [content(50..200), TextField] in 300: content proposed 150 (< its 200
        // ideal) wraps to 150; the field takes 150. Matches SwiftUI proposing
        // remaining/count even to a less-flexible child.
        val out = distributeMainAxis(listOf(content(50, 200), greedy()), available = 300, totalSpacing = 0)
        assertEquals(150, out[0])
        assertEquals(150, out[1])
    }

    // --- Spacing, overflow, and degenerate inputs ---

    @Test
    fun `spacing is removed from the pool before distribution`() {
        // [greedy, greedy] in 300 with 20 total spacing -> 280 split 140/140.
        val out = distributeMainAxis(listOf(greedy(), greedy()), available = 300, totalSpacing = 20)
        assertEquals(140, out[0])
        assertEquals(140, out[1])
    }

    @Test
    fun `children overflow - each takes at least its minimum`() {
        // Two rigid 200s in 300: they can't shrink, so both take 200 (overflow),
        // as a tight Compose Row would also clamp.
        val out = distributeMainAxis(listOf(rigid(200), rigid(200)), available = 300, totalSpacing = 0)
        assertEquals(200, out[0])
        assertEquals(200, out[1])
    }

    @Test
    fun `a single greedy child takes everything`() {
        assertEquals(300, distributeMainAxis(listOf(greedy()), 300, 0)[0])
    }

    @Test
    fun `empty children returns empty`() {
        assertEquals(0, distributeMainAxis(emptyList(), 300, 0).size)
    }

    @Test
    fun `all rigid children keep their sizes regardless of extra space`() {
        val out = distributeMainAxis(listOf(rigid(40), rigid(60)), available = 500, totalSpacing = 0)
        assertEquals(40, out[0])
        assertEquals(60, out[1])
    }

    @Test
    fun `sizing coerces a stray inverted intrinsic instead of throwing`() {
        // ideal < min and max < ideal must not crash a layout pass.
        val s = StackChildSizing.of(min = 100, ideal = 40, max = 10)
        assertEquals(100, s.min)
        assertEquals(100, s.ideal)
        assertEquals(100, s.max)
        assertTrue(s.flexibility == 0L)
    }
}
