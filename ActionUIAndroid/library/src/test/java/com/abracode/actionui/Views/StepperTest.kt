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
 * Unit tests for [Stepper] - a Double-valued control on the state bridge.
 * Exercises the `DOUBLE` [ActionUIValueType] path end-to-end through the real
 * element, plus the pure `range`/`step` resolution ([resolveStepperConfig]), the
 * tap math ([steppedValue]), and label formatting ([stepperLabel]).
 *
 * The `@Composable` Material3 rendering is exercised by running the app, the
 * stance the rest of the renderer takes.
 */
class StepperTest {

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

    private fun element(value: Double) = ActionUIElement(
        id = 1,
        type = "Stepper",
        properties = buildJsonObject { put("value", value) }
    )

    @Test
    fun `registry resolves Stepper and it declares a Double value type`() {
        assertSame(Stepper, ActionUIRegistry.lookup("Stepper"))
        assertEquals(ActionUIValueType.DOUBLE, Stepper.valueType)
    }

    @Test
    fun `initial value comes from the value property, defaulting to zero`() {
        assertEquals(5.0, Stepper.initialValue(element(value = 5.0)))
        assertEquals(0.0, Stepper.initialValue(ActionUIElement(id = 1, type = "Stepper")))
    }

    @Test
    fun `host can read the seeded value and set it from a string`() {
        ActionUIModel.loadDescription(element(value = 5.0), windowUUID = "")

        assertEquals(5.0, ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "8")
        assertEquals(8.0, ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `range is null when absent`() {
        val config = resolveStepperConfig(buildJsonObject { put("value", 1.0) }, CapturingLogger())
        assertNull(config.range)
        assertEquals(1.0, config.step, 0.0)
    }

    @Test
    fun `valid range and step are honored`() {
        val props = buildJsonObject {
            putJsonObject("range") { put("min", 0.0); put("max", 10.0) }
            put("step", 2.0)
        }
        val config = resolveStepperConfig(props, CapturingLogger())
        assertEquals(0.0 to 10.0, config.range)
        assertEquals(2.0, config.step, 0.0)
    }

    @Test
    fun `invalid range with min greater than max warns and is dropped`() {
        val logger = CapturingLogger()
        val props = buildJsonObject { putJsonObject("range") { put("min", 10.0); put("max", 1.0) } }
        val config = resolveStepperConfig(props, logger)
        assertNull(config.range)
        assertTrue(logger.warnings.any { it.contains("min <= max") })
    }

    @Test
    fun `non-positive step warns and defaults to one`() {
        val logger = CapturingLogger()
        val config = resolveStepperConfig(buildJsonObject { put("step", 0.0) }, logger)
        assertEquals(1.0, config.step, 0.0)
        assertTrue(logger.warnings.any { it.contains("positive") })
    }

    @Test
    fun `steppedValue increments and decrements by the step`() {
        assertEquals(6.0, steppedValue(5.0, 1.0, increment = true, range = null), 0.0)
        assertEquals(4.0, steppedValue(5.0, 1.0, increment = false, range = null), 0.0)
        assertEquals(7.5, steppedValue(5.0, 2.5, increment = true, range = null), 0.0)
    }

    @Test
    fun `steppedValue clamps to the range bounds`() {
        val range = 0.0 to 10.0
        assertEquals(10.0, steppedValue(10.0, 1.0, increment = true, range = range), 0.0)
        assertEquals(0.0, steppedValue(0.0, 1.0, increment = false, range = range), 0.0)
        assertEquals(10.0, steppedValue(9.0, 5.0, increment = true, range = range), 0.0)
    }

    @Test
    fun `labelFormat takes precedence and formats the current value`() {
        val props = buildJsonObject { put("label", "ignored"); put("labelFormat", "Count: %.0f") }
        assertEquals("Count: 5", stepperLabel(props, 5.0, CapturingLogger()))
    }

    @Test
    fun `plain label is used when no format is given`() {
        val props = buildJsonObject { put("label", "Quantity") }
        assertEquals("Quantity", stepperLabel(props, 5.0, CapturingLogger()))
        assertEquals("", stepperLabel(buildJsonObject { }, 5.0, CapturingLogger()))
    }

    @Test
    fun `malformed labelFormat warns and falls back to the plain label`() {
        val logger = CapturingLogger()
        // %d is an integer conversion; the value is a Double, so this is malformed.
        val props = buildJsonObject { put("label", "Quantity"); put("labelFormat", "Count: %d") }
        assertEquals("Quantity", stepperLabel(props, 5.0, logger))
        assertTrue(logger.warnings.any { it.contains("labelFormat") })
    }
}
