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
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [NavigationLink] - registry resolution and the pure
 * [resolveLinkTarget] (destinationViewId, inline-destination id, the
 * destinationViewId-wins precedence, and the no-target / id-0 cases). The
 * `@Composable` tappable row is exercised by the app.
 */
class NavigationLinkTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `NavigationLink resolves in the registry`() {
        assertSame(NavigationLink, ActionUIRegistry.lookup("NavigationLink"))
    }

    @Test
    fun `NavigationLink declares an Int value and seeds destinationViewId`() {
        assertEquals(ActionUIValueType.INT, NavigationLink.valueType)
        assertEquals(
            10,
            NavigationLink.initialValue(
                ActionUIElement(id = 1, type = "NavigationLink",
                    properties = buildJsonObject { put("destinationViewId", 10) }),
            ),
        )
        assertNull(NavigationLink.initialValue(ActionUIElement(id = 1, type = "NavigationLink")))
    }

    @Test
    fun `host can read and re-point the link target value`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "NavigationLink",
                properties = buildJsonObject { put("destinationViewId", 10) }),
            windowUUID = "",
        )
        assertEquals(10, ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "20")
        assertEquals(20, ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `resolveLinkTarget reads destinationViewId`() {
        val link = ActionUIElement(
            id = 1, type = "NavigationLink",
            properties = buildJsonObject { put("destinationViewId", 10) },
        )
        assertEquals(10, resolveLinkTarget(link))
    }

    @Test
    fun `resolveLinkTarget falls back to an inline destination id`() {
        val link = ActionUIElement(
            id = 1, type = "NavigationLink",
            destination = ActionUIElement(id = 42, type = "Text"),
        )
        assertEquals(42, resolveLinkTarget(link))
    }

    @Test
    fun `destinationViewId wins over an inline destination`() {
        val link = ActionUIElement(
            id = 1, type = "NavigationLink",
            properties = buildJsonObject { put("destinationViewId", 10) },
            destination = ActionUIElement(id = 42, type = "Text"),
        )
        assertEquals(10, resolveLinkTarget(link))
    }

    @Test
    fun `resolveLinkTarget is null without a target`() {
        assertNull(resolveLinkTarget(ActionUIElement(id = 1, type = "NavigationLink")))
    }

    @Test
    fun `an inline destination without an id is not a target`() {
        val link = ActionUIElement(
            id = 1, type = "NavigationLink",
            destination = ActionUIElement(type = "Text"), // id defaults to 0
        )
        assertNull(resolveLinkTarget(link))
    }
}
