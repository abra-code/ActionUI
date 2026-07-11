package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of `Gauge.kt` - property validation
 * ([resolveGaugeConfig]) and the fraction math ([gaugeFraction]). The
 * indicator rendering is verified by running the app, the stance the rest of
 * the renderer takes for Compose code.
 */
class GaugeTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    private fun element(json: String): ActionUIElement =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    @Test
    fun `Gauge is registered and Double-valued`() {
        assertSame(Gauge, ActionUIRegistry.lookup("Gauge"))
        assertEquals(ActionUIValueType.DOUBLE, Gauge.valueType)
    }

    @Test
    fun `initial value is the value property defaulting to zero`() {
        val withValue = element(
            """{ "type": "Gauge", "id": 1, "properties": { "value": 65 } }"""
        )
        assertEquals(65.0, Gauge.initialValue(withValue))

        val withoutValue = element("""{ "type": "Gauge", "id": 1 }""")
        assertEquals(0.0, Gauge.initialValue(withoutValue))
    }

    @Test
    fun `config defaults match Apple's builder`() {
        val config = resolveGaugeConfig(null, null)
        assertEquals(0.0, config.value, 0.0)
        assertNull(config.title)
        assertNull(config.style)
        assertEquals(0.0, config.min, 0.0)
        assertEquals(1.0, config.max, 0.0)
    }

    @Test
    fun `config reads all properties`() {
        val logger = CapturingLogger()
        val config = resolveGaugeConfig(
            props(
                """{ "value": 65, "title": "Battery", "style": "accessoryCircular",
                     "range": { "min": 0.0, "max": 100.0 } }"""
            ),
            logger
        )
        assertEquals(65.0, config.value, 0.0)
        assertEquals("Battery", config.title)
        assertEquals("accessoryCircular", config.style)
        assertEquals(0.0, config.min, 0.0)
        assertEquals(100.0, config.max, 0.0)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `all four accessory styles are accepted`() {
        val logger = CapturingLogger()
        for (style in listOf(
            "accessoryCircular", "accessoryCircularCapacity",
            "accessoryLinear", "accessoryLinearCapacity",
        )) {
            val config = resolveGaugeConfig(props("""{ "style": "$style" }"""), logger)
            assertEquals(style, config.style)
        }
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid property types warn and fall back to defaults`() {
        val logger = CapturingLogger()
        val config = resolveGaugeConfig(
            props("""{ "value": "high", "title": 7, "style": "fancy", "range": "wide" }"""),
            logger
        )
        assertEquals(0.0, config.value, 0.0)
        assertNull(config.title)
        assertNull(config.style)
        assertEquals(0.0, config.min, 0.0)
        assertEquals(1.0, config.max, 0.0)
        assertEquals(4, logger.warnings.size)
    }

    @Test
    fun `range members are individually defaulted`() {
        val logger = CapturingLogger()
        val config = resolveGaugeConfig(
            props("""{ "range": { "min": "low", "max": 50 } }"""),
            logger
        )
        assertEquals(0.0, config.min, 0.0)
        assertEquals(50.0, config.max, 0.0)
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `fraction is the position within the range clamped`() {
        assertEquals(0.65f, gaugeFraction(0.0, 100.0, 65.0), 1e-6f)
        assertEquals(0.5f, gaugeFraction(-1.0, 1.0, 0.0), 1e-6f)
        assertEquals(0f, gaugeFraction(0.0, 1.0, -2.0), 0f)
        assertEquals(1f, gaugeFraction(0.0, 1.0, 7.0), 0f)
    }

    @Test
    fun `degenerate range renders empty instead of dividing by zero`() {
        assertEquals(0f, gaugeFraction(5.0, 5.0, 5.0), 0f)
        assertEquals(0f, gaugeFraction(10.0, 0.0, 5.0), 0f)
    }

    @Test
    fun `circular gauge uses SwiftUI's accessory-circular intrinsic diameter`() {
        // The ring is a fixed intrinsic diameter that scaleEffect scales (the SwiftUI
        // model, shared with Web's 71px base). No parent measurement / fill.
        assertEquals(71f, CircularGaugeIntrinsicSide.value, 1e-4f)
        assertEquals(40f, CircularGaugeM3Side.value, 1e-4f)
    }

    @Test
    fun `circular stroke is a fixed fraction of the M3 default diameter`() {
        // In the M3 indicator's native (pre-scale) space; the inner scale to the
        // intrinsic diameter then keeps the visual stroke ~8% of the ring.
        assertEquals(40f * 0.08f, circularGaugeStrokeWidth().value, 1e-4f)
    }
}
