package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [Slider] - the first Double-valued control on the state bridge
 * (entry 17). Exercises the `DOUBLE` [ActionUIValueType] path end-to-end through
 * the real element, plus the pure `range`/`step` resolution
 * ([resolveSliderConfig]) and the step-size -> Compose-`steps` conversion
 * ([sliderStepCount]).
 *
 * The `@Composable` Material3 [androidx.compose.material3.Slider] rendering is
 * exercised by running the app, the stance the rest of the renderer takes.
 */
class SliderTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `registry resolves Slider and it declares a Double value type`() {
        assertSame(Slider, ActionUIRegistry.lookup("Slider"))
        assertEquals(ActionUIValueType.DOUBLE, Slider.valueType)
    }

    @Test
    fun `initial value comes from the value property, defaulting to zero`() {
        assertEquals(25.0, Slider.initialValue(element(value = 25.0)))
        assertEquals(0.0, Slider.initialValue(ActionUIElement(id = 1, type = "Slider")))
    }

    @Test
    fun `host can read the seeded value and set it from a string`() {
        ActionUIModel.loadDescription(element(value = 25.0), windowUUID = "")

        assertEquals(25.0, ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "75")
        assertEquals(75.0, ActionUIModel.getElementValue(viewID = 1))
        assertEquals("75.0", ActionUIModel.getElementValueAsString(viewID = 1))
    }

    @Test
    fun `setElementValueFromString warns on a non-numeric string`() {
        val logger = CapturingLogger()
        ActionUIModel.logger = logger
        ActionUIModel.loadDescription(element(value = 1.0), windowUUID = "")

        ActionUIModel.setElementValueFromString(viewID = 1, value = "loud")

        assertEquals(1.0, ActionUIModel.getElementValue(viewID = 1))
        assertTrue(logger.warnings.any { it.contains("Double") })
    }

    @Test
    fun `range defaults to zero-one when absent`() {
        val config = resolveSliderConfig(buildJsonObject { put("value", 0.5) }, CapturingLogger())
        assertEquals(0.0, config.min, 0.0)
        assertEquals(1.0, config.max, 0.0)
        assertNull(config.step)
    }

    @Test
    fun `valid range and step are honored`() {
        val props = buildJsonObject {
            putJsonObject("range") { put("min", 0.0); put("max", 100.0) }
            put("step", 5.0)
        }
        val config = resolveSliderConfig(props, CapturingLogger())
        assertEquals(0.0, config.min, 0.0)
        assertEquals(100.0, config.max, 0.0)
        assertEquals(5.0, config.step)
    }

    @Test
    fun `invalid range with min greater than max warns and defaults`() {
        val logger = CapturingLogger()
        val props = buildJsonObject { putJsonObject("range") { put("min", 10.0); put("max", 1.0) } }
        val config = resolveSliderConfig(props, logger)
        assertEquals(0.0, config.min, 0.0)
        assertEquals(1.0, config.max, 0.0)
        assertTrue(logger.warnings.any { it.contains("min <= max") })
    }

    @Test
    fun `step exceeding the range size is clamped`() {
        val logger = CapturingLogger()
        val props = buildJsonObject {
            putJsonObject("range") { put("min", 0.0); put("max", 10.0) }
            put("step", 25.0)
        }
        val config = resolveSliderConfig(props, logger)
        assertEquals(10.0, config.step)
        assertTrue(logger.warnings.any { it.contains("clamping") })
    }

    @Test
    fun `non-positive step warns and defaults to one`() {
        val logger = CapturingLogger()
        val props = buildJsonObject {
            putJsonObject("range") { put("min", 0.0); put("max", 100.0) }
            put("step", -3.0)
        }
        val config = resolveSliderConfig(props, logger)
        assertEquals(1.0, config.step)
        assertTrue(logger.warnings.any { it.contains("positive") })
    }

    @Test
    fun `step count converts a step size to intermediate stops`() {
        // 0..100 step 1 -> 99 stops between the endpoints.
        assertEquals(99, sliderStepCount(0.0, 100.0, 1.0))
        // 0..10 step 2 -> 4 stops.
        assertEquals(4, sliderStepCount(0.0, 10.0, 2.0))
        // No / non-positive step, or degenerate range -> continuous (0).
        assertEquals(0, sliderStepCount(0.0, 1.0, null))
        assertEquals(0, sliderStepCount(0.0, 1.0, 0.0))
        assertEquals(0, sliderStepCount(5.0, 5.0, 1.0))
    }

    private fun element(value: Double): ActionUIElement =
        ActionUIElement(id = 1, type = "Slider", properties = buildJsonObject { put("value", value) })
}
