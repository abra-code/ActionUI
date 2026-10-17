package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [Chart], the "Chart Unavailable" placeholder: registry
 * resolution, the String value (the selection, `""` at load), the rows API, and a
 * replaced description, all without warnings. The `@Composable` placeholder is
 * [ContentUnavailableView]'s and is exercised by the app.
 */
class ChartTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning || level == LoggerLevel.error) warnings.add(message)
        }
    }

    private lateinit var logger: CapturingLogger

    private val description = buildJsonObject {
        put("columns", buildJsonArray { add(JsonPrimitive("day")) })
        put("data", buildJsonArray { add(buildJsonArray { add(JsonPrimitive("Mon")) }) })
        put("content", buildJsonArray {})
    }

    @Before
    fun setUp() {
        logger = CapturingLogger()
        ActionUIModel.logger = logger
        ActionUIModel.loadDescription(
            ActionUIElement(id = 10, type = "Chart", properties = buildJsonObject { put("chart", description) }),
            windowUUID = "",
        )
    }

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `registry resolves Chart and it declares a String value`() {
        assertSame(Chart, ActionUIRegistry.lookup("Chart"))
        assertEquals(ActionUIValueType.STRING, Chart.valueType)
    }

    @Test
    fun `the placeholder says the chart is unavailable`() {
        assertEquals("Chart Unavailable", ContentUnavailableView.initialValue(Chart.placeholder))
        assertEquals(0, Chart.placeholder.id)
    }

    @Test
    fun `the selection value starts empty and takes a host value`() {
        assertEquals("", ActionUIModel.getElementValue(viewID = 10))
        ActionUIModel.setElementValueFromString(viewID = 10, value = "{\"x\":\"Tue\"}")
        assertEquals("{\"x\":\"Tue\"}", ActionUIModel.getElementValue(viewID = 10))
        assertEquals(emptyList<String>(), logger.warnings)
    }

    @Test
    fun `the rows API reads and writes the rows`() {
        assertEquals(emptyList<List<String>>(), ActionUIModel.getElementRows(viewID = 10))
        ActionUIModel.setElementRows(viewID = 10, rows = listOf(listOf("Mon", "3")))
        ActionUIModel.appendElementRows(viewID = 10, rows = listOf(listOf("Tue", "5")))
        assertEquals(listOf(listOf("Mon", "3"), listOf("Tue", "5")), ActionUIModel.getElementRows(viewID = 10))
        ActionUIModel.clearElementRows(viewID = 10)
        assertEquals(emptyList<List<String>>(), ActionUIModel.getElementRows(viewID = 10))
        assertEquals(emptyList<String>(), logger.warnings)
    }

    @Test
    fun `a replaced description is stored`() {
        ActionUIModel.setElementProperty(viewID = 10, propertyName = "chart", value = mapOf("content" to emptyList<Any>()))
        assertEquals(mapOf("content" to emptyList<Any>()), ActionUIModel.getElementProperty(viewID = 10, propertyName = "chart"))
        assertEquals(emptyList<String>(), logger.warnings)
    }
}
