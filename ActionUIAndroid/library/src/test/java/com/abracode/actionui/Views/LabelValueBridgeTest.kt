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
 * Unit tests for [Label]'s value bridge - the [ActionUIValueType.STRING] parity
 * with SwiftUI (`ActionUI/Views/Label.swift`): the mutable runtime value is the
 * title string, seeded from `title` and host-settable at runtime. The icon is
 * not part of the value (Apple parity). The `@Composable` row is exercised by
 * the app.
 */
class LabelValueBridgeTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `Label resolves and declares a String value`() {
        assertSame(Label, ActionUIRegistry.lookup("Label"))
        assertEquals(ActionUIValueType.STRING, Label.valueType)
    }

    @Test
    fun `initial value is the title property defaulting to empty`() {
        assertEquals(
            "Favorites",
            Label.initialValue(ActionUIElement(id = 1, type = "Label",
                properties = buildJsonObject { put("title", "Favorites") })),
        )
        assertEquals("", Label.initialValue(ActionUIElement(id = 1, type = "Label")))
    }

    @Test
    fun `host can read and update the title value`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "Label",
                properties = buildJsonObject { put("title", "Favorites"); put("systemImage", "star.fill") }),
            windowUUID = "",
        )
        assertEquals("Favorites", ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "Bookmarks")
        assertEquals("Bookmarks", ActionUIModel.getElementValue(viewID = 1))
    }
}
