package com.abracode.actionui.Helpers

import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.TweenSpec
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.ViewModel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI

/**
 * Unit tests for the `animation` modifier's pure halves
 * (`Helpers/AnimationHelper.kt`): config parsing with the Swift `View.swift`
 * validation semantics, the SwiftUI-curve -> Compose-spec mapping, and the
 * watched-value resolution order. The composition-bound half ([ElementAnimator]
 * driving `Animatable`s) is exercised on the emulator via the demo.
 */
class AnimationHelperTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private val logger = CapturingLogger()

    // MARK: - Parsing: string shorthand

    @Test
    fun `string shorthand normalizes to a curve-only config`() {
        val props = buildJsonObject { put("animation", "spring") }
        assertEquals(AnimationConfig("spring"), resolveAnimationConfig(props, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid shorthand curve warns and yields no config`() {
        val props = buildJsonObject { put("animation", "wobbly") }
        assertNull(resolveAnimationConfig(props, logger))
        assertTrue(logger.warnings.any { it.contains("Invalid animation curve 'wobbly'") })
    }

    @Test
    fun `absent animation yields no config and no warning`() {
        assertNull(resolveAnimationConfig(buildJsonObject { put("title", "x") }, logger))
        assertNull(resolveAnimationConfig(null, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `non-string non-object animation warns and yields no config`() {
        val props = buildJsonObject { put("animation", 3) }
        assertNull(resolveAnimationConfig(props, logger))
        assertTrue(logger.warnings.any { it.contains("Invalid animation curve") })
    }

    // MARK: - Parsing: dictionary form

    @Test
    fun `full dictionary form parses every knob`() {
        val props = buildJsonObject {
            putJsonObject("animation") {
                put("curve", "easeOut")
                put("duration", 0.3)
                put("delay", 0.1)
                put("speed", 2.0)
                put("value", "opacity")
            }
        }
        assertEquals(
            AnimationConfig("easeOut", durationSec = 0.3, delaySec = 0.1, speed = 2.0, watchedKey = "opacity"),
            resolveAnimationConfig(props, logger)
        )
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `missing or invalid curve drops the whole dictionary with a warning`() {
        val missing = buildJsonObject { putJsonObject("animation") { put("duration", 0.3) } }
        assertNull(resolveAnimationConfig(missing, logger))

        val invalid = buildJsonObject { putJsonObject("animation") { put("curve", "wobbly") } }
        assertNull(resolveAnimationConfig(invalid, logger))
        assertEquals(2, logger.warnings.count { it.contains("animation.curve") })
    }

    @Test
    fun `invalid optional knobs are dropped individually with warnings`() {
        val props = buildJsonObject {
            putJsonObject("animation") {
                put("curve", "spring")
                put("duration", -1)
                put("delay", -0.5)
                put("speed", 0)
                put("value", 7)
            }
        }
        assertEquals(AnimationConfig("spring"), resolveAnimationConfig(props, logger))
        assertTrue(logger.warnings.any { it.contains("animation.duration") })
        assertTrue(logger.warnings.any { it.contains("animation.delay") })
        assertTrue(logger.warnings.any { it.contains("animation.speed") })
        assertTrue(logger.warnings.any { it.contains("animation.value") })
    }

    // MARK: - Spec mapping: duration curves -> tween

    @Test
    fun `linear maps to a tween with SwiftUI's default duration`() {
        val spec = AnimationConfig("linear").animationSpec<Float>() as TweenSpec<Float>
        assertEquals(350, spec.durationMillis)
        assertEquals(LinearEasing, spec.easing)
    }

    @Test
    fun `tween duration honors the duration knob and the speed divisor`() {
        val spec = AnimationConfig("easeInOut", durationSec = 0.2, speed = 2.0)
            .animationSpec<Float>() as TweenSpec<Float>
        assertEquals(100, spec.durationMillis)
        assertEquals(EaseInOut, spec.easing)
    }

    // MARK: - Spec mapping: spring curves

    private fun stiffness(responseSec: Double): Float =
        ((2 * PI / responseSec) * (2 * PI / responseSec)).toFloat()

    @Test
    fun `spring curves map to SwiftUI's damping fractions`() {
        val cases = mapOf(
            "spring" to 0.825f, "bouncy" to 0.7f, "smooth" to 1.0f,
            "snappy" to 0.85f, "interactiveSpring" to 0.86f, "default" to 1.0f,
        )
        for ((curve, damping) in cases) {
            val spec = AnimationConfig(curve).animationSpec<Float>() as SpringSpec<Float>
            assertEquals("curve $curve", damping, spec.dampingRatio, 0.001f)
        }
    }

    @Test
    fun `spring stiffness derives from the response time`() {
        val spec = AnimationConfig("spring").animationSpec<Float>() as SpringSpec<Float>
        assertEquals(stiffness(0.5), spec.stiffness, 0.1f)

        val slow = AnimationConfig("spring", durationSec = 1.0).animationSpec<Float>() as SpringSpec<Float>
        assertEquals(stiffness(1.0), slow.stiffness, 0.1f)
    }

    @Test
    fun `default and interactiveSpring ignore the duration knob like the Swift switch`() {
        val default = AnimationConfig("default", durationSec = 3.0).animationSpec<Float>() as SpringSpec<Float>
        assertEquals(stiffness(0.55), default.stiffness, 0.1f)

        val interactive = AnimationConfig("interactiveSpring", durationSec = 3.0).animationSpec<Float>() as SpringSpec<Float>
        assertEquals(stiffness(0.15), interactive.stiffness, 0.5f)
    }

    @Test
    fun `speed scales spring stiffness quadratically (time scaling)`() {
        val spec = AnimationConfig("spring", speed = 2.0).animationSpec<Float>() as SpringSpec<Float>
        assertEquals(stiffness(0.5) * 4, spec.stiffness, 0.5f)
    }

    @Test
    fun `delay scales with speed like durations`() {
        assertEquals(300, AnimationConfig("spring", delaySec = 0.3).delayMillis())
        assertEquals(150, AnimationConfig("spring", delaySec = 0.3, speed = 2.0).delayMillis())
        assertEquals(0, AnimationConfig("spring").delayMillis())
    }

    // MARK: - Watched-value resolution (Swift resolveAnimationWatchedValue order)

    @Test
    fun `no named key watches the mutation token`() {
        val viewModel = ViewModel()
        assertEquals(0, resolveAnimationWatchedValue(null, viewModel, null))
        viewModel.mutationToken = 3
        assertEquals(3, resolveAnimationWatchedValue(null, viewModel, null))
        assertEquals(0, resolveAnimationWatchedValue(null, null, null))
    }

    @Test
    fun `a named key resolves property first then state then value`() {
        val viewModel = ViewModel()
        viewModel.states["opacity"] = 0.9
        val props = buildJsonObject { put("opacity", 0.5) }

        // Property (effective, overrides included by the caller) wins over state.
        assertEquals(props["opacity"], resolveAnimationWatchedValue("opacity", viewModel, props))
        // Without the property, the state key answers.
        assertEquals(0.9, resolveAnimationWatchedValue("opacity", viewModel, null))
    }

    @Test
    fun `the literal value key reads the element's runtime value`() {
        val viewModel = ViewModel()
        viewModel.value = "current"
        assertEquals("current", resolveAnimationWatchedValue("value", viewModel, null))
    }

    @Test
    fun `an unresolved key reads as a constant`() {
        assertEquals(0, resolveAnimationWatchedValue("nope", ViewModel(), buildJsonObject { }))
    }
}
