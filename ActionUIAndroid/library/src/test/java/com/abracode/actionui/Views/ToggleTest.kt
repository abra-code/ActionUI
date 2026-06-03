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
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [Toggle] - the first Boolean-valued control on the state bridge
 * (entry 17). Exercises the `BOOLEAN` [ActionUIValueType] path end-to-end through
 * the real element (not a fake builder): initial value from `isOn`, and a host
 * `setElementValueFromString("true")` round-tripping through the `ViewModel`.
 * Style resolution is covered as a pure helper.
 *
 * The `@Composable` rendering itself (Switch / Checkbox layout) is exercised by
 * running the app, the stance the rest of the renderer takes for Compose code.
 */
class ToggleTest {

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
    fun `registry resolves Toggle to the builder`() {
        assertSame(Toggle, ActionUIRegistry.lookup("Toggle"))
    }

    @Test
    fun `declares a Boolean value type`() {
        assertEquals(ActionUIValueType.BOOLEAN, Toggle.valueType)
    }

    @Test
    fun `initial value comes from isOn, defaulting to false`() {
        assertEquals(true, Toggle.initialValue(element(isOn = true)))
        assertEquals(false, Toggle.initialValue(element(isOn = false)))
        assertEquals(false, Toggle.initialValue(ActionUIElement(id = 1, type = "Toggle")))
    }

    @Test
    fun `host can read the seeded value and flip it from a string`() {
        ActionUIModel.loadDescription(element(id = 1, isOn = false), windowUUID = "")

        assertEquals(false, ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "true")
        assertEquals(true, ActionUIModel.getElementValue(viewID = 1))
        assertEquals("true", ActionUIModel.getElementValueAsString(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "false")
        assertEquals(false, ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `setElementValueFromString warns on a non-boolean string`() {
        val logger = CapturingLogger()
        ActionUIModel.logger = logger
        ActionUIModel.loadDescription(element(id = 1, isOn = false), windowUUID = "")

        ActionUIModel.setElementValueFromString(viewID = 1, value = "maybe")

        assertEquals(false, ActionUIModel.getElementValue(viewID = 1))
        assertTrue(logger.warnings.any { it.contains("Boolean") })
    }

    @Test
    fun `style resolves switch and checkbox, downgrading button and unknown`() {
        val logger = CapturingLogger()
        assertEquals(ToggleStyle.Switch, resolveToggleStyle(null, logger))
        assertEquals(ToggleStyle.Switch, resolveToggleStyle("switch", logger))
        assertEquals(ToggleStyle.Checkbox, resolveToggleStyle("checkbox", logger))
        assertEquals(ToggleStyle.Switch, resolveToggleStyle("button", logger))
        assertEquals(ToggleStyle.Switch, resolveToggleStyle("bogus", logger))
        assertTrue(logger.warnings.any { it.contains("button") })
        assertTrue(logger.warnings.any { it.contains("bogus") })
    }

    private fun element(id: Int = 1, isOn: Boolean): ActionUIElement =
        ActionUIElement(id = id, type = "Toggle", properties = buildJsonObject { put("isOn", isOn) })
}
