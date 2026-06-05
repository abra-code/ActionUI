package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
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

    @Test
    fun `NavigationLink resolves in the registry`() {
        assertSame(NavigationLink, ActionUIRegistry.lookup("NavigationLink"))
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
