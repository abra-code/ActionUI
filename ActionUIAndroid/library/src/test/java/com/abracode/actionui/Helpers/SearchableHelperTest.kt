package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [resolveSearchable] - the read-time validation of the
 * `searchable` property modifier (`SearchableHelper.kt`), mirroring Apple's
 * `validateProperties` searchable block: a dictionary with a non-empty String
 * `actionID` and an optional String `prompt`. The Material3 field presentation
 * itself is exercised by running the app, the stance the renderer takes for
 * Compose code.
 */
class SearchableHelperTest {

    private class RecordingLogger : ActionUILogger {
        val messages = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            messages.add(message)
        }
    }

    /** Reads the `properties` object out of a single-element document. */
    private fun propertiesOf(json: String) =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json).properties

    @Test
    fun `valid searchable resolves actionID and prompt`() {
        val props = propertiesOf(
            """{ "type": "List", "properties": { "searchable": { "actionID": "demo.search", "prompt": "Find" } } }"""
        )
        val logger = RecordingLogger()
        val config = resolveSearchable(props, logger)
        assertEquals(SearchableConfig("demo.search", "Find"), config)
        assertTrue(logger.messages.isEmpty())
    }

    @Test
    fun `prompt is optional`() {
        val props = propertiesOf(
            """{ "type": "List", "properties": { "searchable": { "actionID": "demo.search" } } }"""
        )
        val config = resolveSearchable(props, null)
        assertEquals(SearchableConfig("demo.search", null), config)
    }

    @Test
    fun `absent searchable resolves to null without warning`() {
        val props = propertiesOf("""{ "type": "List", "properties": { "navigationTitle": "Receivers" } }""")
        val logger = RecordingLogger()
        assertNull(resolveSearchable(props, logger))
        assertTrue(logger.messages.isEmpty())
    }

    @Test
    fun `missing actionID is dropped with a warning`() {
        val props = propertiesOf(
            """{ "type": "List", "properties": { "searchable": { "prompt": "Find" } } }"""
        )
        val logger = RecordingLogger()
        assertNull(resolveSearchable(props, logger))
        assertTrue(logger.messages.single().contains("non-empty String 'actionID'"))
    }

    @Test
    fun `empty actionID is dropped with a warning`() {
        val props = propertiesOf(
            """{ "type": "List", "properties": { "searchable": { "actionID": "" } } }"""
        )
        val logger = RecordingLogger()
        assertNull(resolveSearchable(props, logger))
        assertTrue(logger.messages.single().contains("non-empty String 'actionID'"))
    }

    @Test
    fun `non-object searchable is dropped with a warning`() {
        val props = propertiesOf(
            """{ "type": "List", "properties": { "searchable": "demo.search" } }"""
        )
        val logger = RecordingLogger()
        assertNull(resolveSearchable(props, logger))
        assertTrue(logger.messages.single().contains("expected dictionary"))
    }

    @Test
    fun `non-string prompt is stripped but the modifier is kept`() {
        val props = propertiesOf(
            """{ "type": "List", "properties": { "searchable": { "actionID": "demo.search", "prompt": 42 } } }"""
        )
        val logger = RecordingLogger()
        val config = resolveSearchable(props, logger)
        assertEquals(SearchableConfig("demo.search", null), config)
        assertTrue(logger.messages.single().contains("searchable.prompt"))
    }
}
