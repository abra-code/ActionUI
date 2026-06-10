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
 * Unit tests for [DisclosureGroup] - the first Android element to use the
 * observable *state* side of the bridge (`states["isExpanded"]`). Covers registry
 * resolution, [DisclosureGroup.initialStates], and the end-to-end seed + host
 * read/write path. The `@Composable` header / chevron is exercised by the app.
 */
class DisclosureGroupTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    private fun element(expanded: Boolean) = ActionUIElement(
        id = 1, type = "DisclosureGroup",
        properties = buildJsonObject { put("isExpanded", expanded) }
    )

    @Test
    fun `registry resolves DisclosureGroup and it carries no value`() {
        assertSame(DisclosureGroup, ActionUIRegistry.lookup("DisclosureGroup"))
        assertEquals(ActionUIValueType.NONE, DisclosureGroup.valueType)
    }

    @Test
    fun `initialStates reflects the isExpanded property, defaulting to false`() {
        assertEquals(
            mapOf("isExpanded" to true, "content" to emptyList<List<String>>()),
            DisclosureGroup.initialStates(element(expanded = true)),
        )
        assertEquals(
            mapOf("isExpanded" to false, "content" to emptyList<List<String>>()),
            DisclosureGroup.initialStates(ActionUIElement(id = 1, type = "DisclosureGroup"))
        )
    }

    @Test
    fun `host can read the seeded isExpanded state and set it from a string`() {
        ActionUIModel.loadDescription(element(expanded = true), windowUUID = "")

        assertEquals(true, ActionUIModel.getElementState(viewID = 1, key = "isExpanded"))

        ActionUIModel.setElementStateFromString(viewID = 1, key = "isExpanded", value = "false")
        assertEquals(false, ActionUIModel.getElementState(viewID = 1, key = "isExpanded"))
    }
}
