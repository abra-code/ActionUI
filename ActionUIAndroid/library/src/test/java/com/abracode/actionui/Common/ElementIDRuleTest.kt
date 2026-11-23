package com.abracode.actionui.Common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Only positive ids register. A negative id from JSON is dropped when it is decoded, with a warning; two
 * elements of one ActionUI JSON with one id share a state, which is logged. The same rules as the Swift core's.
 */
class ElementIDRuleTest {

    private class RecordingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        val errors = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings += message
            if (level == LoggerLevel.error) errors += message
        }
    }

    @Test
    fun `a negative id from JSON is dropped, with a warning`() {
        val logger = RecordingLogger()
        val decoded = ActionUIElement(id = 1, type = "VStack", children = listOf(
            ActionUIElement(id = -9, type = "Text"), ActionUIElement(id = 3, type = "Text"))).droppingUntypedElements(logger)
        assertEquals(listOf(0, 3), decoded.children?.map { it.id })
        assertEquals(listOf("Ignoring id -9 on Text: an id must be a positive integer"), logger.warnings)
        val window = WindowModel(windowUUID = "ids", logger = logger)
        window.loadDescription(decoded)
        assertNull(window.viewModels[-9])
    }

    @Test
    fun `a duplicate id within one load is logged`() {
        val logger = RecordingLogger()
        val window = WindowModel(windowUUID = "ids", logger = logger)
        window.loadDescription(ActionUIElement(id = 1, type = "VStack", children = listOf(
            ActionUIElement(id = 2, type = "Text"),
            ActionUIElement(id = 3, type = "HStack", children = listOf(ActionUIElement(id = 2, type = "Button"))))))
        assertEquals(listOf("Duplicate id 2 in window ids: its elements share one state"), logger.errors)
        // Elements without an id (0) are not counted.
        val quiet = RecordingLogger()
        WindowModel(windowUUID = "ids", logger = quiet).loadDescription(ActionUIElement(type = "VStack", children = listOf(
            ActionUIElement(type = "Text"), ActionUIElement(type = "Text"))))
        assertEquals(emptyList<String>(), quiet.errors + quiet.warnings)
    }
}
