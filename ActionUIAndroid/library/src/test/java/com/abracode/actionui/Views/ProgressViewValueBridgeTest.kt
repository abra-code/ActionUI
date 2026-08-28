package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ProgressView]'s value bridge - the [ActionUIValueType.DOUBLE]
 * parity with SwiftUI (Apple's `Double?`, `ActionUI/Views/ProgressView.swift`):
 * a host can drive the progress at runtime; [ProgressView.initialValue] returns
 * null (use the static `value` property). The `@Composable` indicator is
 * exercised by the app.
 */
class ProgressViewValueBridgeTest {

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
    fun `ProgressView resolves and declares a Double value with a null initial seed`() {
        assertSame(ProgressView, ActionUIRegistry.lookup("ProgressView"))
        assertEquals(ActionUIValueType.DOUBLE, ProgressView.valueType)
        // Apple's initialValue returns model.value (null until a host sets it).
        assertNull(ProgressView.initialValue(ActionUIElement(id = 1, type = "ProgressView",
            properties = buildJsonObject { put("value", 0.5) })))
    }

    @Test
    fun `host can drive the progress value through the string bridge`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "ProgressView",
                properties = buildJsonObject { put("value", 0.5) }),
            windowUUID = "",
        )
        // No seeded value: the static `value` property drives the bar until a write.
        assertNull(ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "0.75")
        assertEquals(0.75, ActionUIModel.getElementValue(viewID = 1))
        assertEquals("0.75", ActionUIModel.getElementValueAsString(viewID = 1))
    }

    @Test
    fun `progressViewStyle resolves automatic, linear and circular`() {
        val logger = CapturingLogger()
        assertEquals(ProgressViewStyle.Automatic, resolveProgressViewStyle(null, logger))
        assertEquals(ProgressViewStyle.Automatic, resolveProgressViewStyle("automatic", logger))
        // "linear" is the one the property exists for: a bar even when the
        // progress is indeterminate, which the automatic pairing draws as a
        // spinner.
        assertEquals(ProgressViewStyle.Linear, resolveProgressViewStyle("linear", logger))
        assertEquals(ProgressViewStyle.Circular, resolveProgressViewStyle("circular", logger))
        assertEquals(ProgressViewStyle.Automatic, resolveProgressViewStyle("bogus", logger))
        assertTrue(logger.warnings.any { it.contains("bogus") })
    }
}
