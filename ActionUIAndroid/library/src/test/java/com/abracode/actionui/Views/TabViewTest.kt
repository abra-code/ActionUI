package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [TabView] / [Tab] - registry resolution, the INT selection value
 * (seed + default), and the pure [tabTitle]. The `@Composable` NavigationBar /
 * content swap is exercised by the app.
 */
class TabViewTest {

    @Test
    fun `TabView and Tab resolve in the registry`() {
        assertSame(TabView, ActionUIRegistry.lookup("TabView"))
        assertSame(Tab, ActionUIRegistry.lookup("Tab"))
    }

    @Test
    fun `TabView is INT-valued and seeds the selection index`() {
        assertEquals(ActionUIValueType.INT, TabView.valueType)
        val el = ActionUIElement(id = 1, type = "TabView", properties = buildJsonObject { put("selection", 2) })
        assertEquals(2, TabView.initialValue(el))
    }

    @Test
    fun `selection defaults to 0`() {
        assertEquals(0, TabView.initialValue(ActionUIElement(id = 1, type = "TabView")))
    }

    @Test
    fun `tabTitle reads the title and defaults to Tab`() {
        val titled = ActionUIElement(type = "Tab", properties = buildJsonObject { put("title", "Home") })
        assertEquals("Home", tabTitle(titled))
        assertEquals("Tab", tabTitle(ActionUIElement(type = "Tab")))
    }

    @Test
    fun `Tab carries no value`() {
        assertEquals(ActionUIValueType.NONE, Tab.valueType)
    }
}
