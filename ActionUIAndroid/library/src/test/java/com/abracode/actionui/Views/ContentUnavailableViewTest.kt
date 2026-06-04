package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [ContentUnavailableView] - registry resolution, the `STRING`
 * value path ([ContentUnavailableView.initialValue] for both the title and
 * search variants), the search-message builder
 * ([contentUnavailableSearchText]), and a host value round-trip. The
 * `@Composable` centered column is exercised by the app.
 */
class ContentUnavailableViewTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `registry resolves ContentUnavailableView and it declares a String value`() {
        assertSame(ContentUnavailableView, ActionUIRegistry.lookup("ContentUnavailableView"))
        assertEquals(ActionUIValueType.STRING, ContentUnavailableView.valueType)
    }

    @Test
    fun `initial value is the title, defaulting to No Content`() {
        assertEquals(
            "No Results",
            ContentUnavailableView.initialValue(
                ActionUIElement(id = 1, type = "ContentUnavailableView",
                    properties = buildJsonObject { put("title", "No Results") })
            )
        )
        assertEquals(
            "No Content",
            ContentUnavailableView.initialValue(ActionUIElement(id = 1, type = "ContentUnavailableView"))
        )
    }

    @Test
    fun `search variant seeds the query as the value`() {
        val element = ActionUIElement(
            id = 1, type = "ContentUnavailableView",
            properties = buildJsonObject { put("search", true); put("query", "planets") }
        )
        assertEquals("planets", ContentUnavailableView.initialValue(element))
    }

    @Test
    fun `search text reflects the query`() {
        assertEquals("No Results", contentUnavailableSearchText(""))
        assertEquals("No Results for \"planets\"", contentUnavailableSearchText("planets"))
    }

    @Test
    fun `host can read and update the message value`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "ContentUnavailableView",
                properties = buildJsonObject { put("title", "No Results") }),
            windowUUID = ""
        )
        assertEquals("No Results", ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "Nothing here")
        assertEquals("Nothing here", ActionUIModel.getElementValue(viewID = 1))
    }
}
