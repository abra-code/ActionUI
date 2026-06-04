package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ListView] - registry resolution, the deferred value side, the
 * empty-rows seed, and the pure homogeneous [resolveItemType] (Text default,
 * Button, the Image/AsyncImage downgrade, and the warn-and-default paths). The
 * `@Composable` LazyColumn / template / row surfaces are exercised by the app.
 */
class ListTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @Test
    fun `canonical List resolves to ListView and exposes the selection value`() {
        assertSame(ListView, ActionUIRegistry.lookup("List"))
        // Selection is the Apple-parity [String] value (B6 value-bridge type).
        assertEquals(ActionUIValueType.STRING_LIST, ListView.valueType)
        // Nothing selected initially.
        assertEquals(emptyList<String>(), ListView.initialValue(ActionUIElement(id = 1, type = "List")))
    }

    @Test
    fun `seeds empty rows so a host can address them by id`() {
        assertEquals(
            mapOf("content" to emptyList<List<String>>()),
            ListView.initialStates(ActionUIElement(id = 1, type = "List")),
        )
    }

    @Test
    fun `itemType defaults to a Text cell`() {
        val logger = CapturingLogger()
        val resolved = resolveItemType(null, logger)
        assertEquals("Text", resolved.viewType)
        assertEquals("title", resolved.actionContext)
        assertNull(resolved.actionID)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `Button itemType keeps its actionContext and actionID`() {
        val logger = CapturingLogger()
        val props = buildJsonObject {
            putJsonObject("itemType") {
                put("viewType", "Button")
                put("actionContext", "rowIndex")
                put("actionID", "row.tap")
            }
        }
        val resolved = resolveItemType(props, logger)
        assertEquals("Button", resolved.viewType)
        assertEquals("rowIndex", resolved.actionContext)
        assertEquals("row.tap", resolved.actionID)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `Image itemType downgrades to Text with a warning`() {
        val logger = CapturingLogger()
        val props = buildJsonObject { putJsonObject("itemType") { put("viewType", "Image") } }
        val resolved = resolveItemType(props, logger)
        assertEquals("Text", resolved.viewType)
        assertTrue(logger.warnings.any { it.contains("image", ignoreCase = true) })
    }

    @Test
    fun `unknown viewType warns and defaults to Text`() {
        val logger = CapturingLogger()
        val props = buildJsonObject { putJsonObject("itemType") { put("viewType", "Widget") } }
        assertEquals("Text", resolveItemType(props, logger).viewType)
        assertTrue(logger.warnings.any { it.contains("invalid") })
    }

    @Test
    fun `unknown actionContext warns and defaults to title`() {
        val logger = CapturingLogger()
        val props = buildJsonObject {
            putJsonObject("itemType") { put("viewType", "Button"); put("actionContext", "bogus") }
        }
        assertEquals("title", resolveItemType(props, logger).actionContext)
        assertTrue(logger.warnings.any { it.contains("actionContext") })
    }
}
