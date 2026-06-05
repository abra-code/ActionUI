package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure toolbar resolution in `ToolbarHelper.kt` -
 * [resolveToolbarSlot] (placement -> slot) and [resolveToolbar] (a `toolbar` array
 * -> chrome buckets, incl. group flattening, overflow, and the unsupported-drop
 * warning). The `@Composable` `ToolbarHost` / Scaffold is exercised by the app.
 */
class ToolbarHelperTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @Test
    fun `resolveToolbarSlot maps every placement`() {
        listOf(null, "automatic", "topBarTrailing", "confirmationAction", "destructiveAction", "primaryAction")
            .forEach { assertEquals(ToolbarSlot.Trailing, resolveToolbarSlot(it)) }
        assertEquals(ToolbarSlot.Leading, resolveToolbarSlot("topBarLeading"))
        assertEquals(ToolbarSlot.Leading, resolveToolbarSlot("cancellationAction"))
        assertEquals(ToolbarSlot.Principal, resolveToolbarSlot("principal"))
        assertEquals(ToolbarSlot.Overflow, resolveToolbarSlot("secondaryAction"))
        assertEquals(ToolbarSlot.Bottom, resolveToolbarSlot("bottomBar"))
        listOf("keyboard", "navigation", "status")
            .forEach { assertEquals(ToolbarSlot.Unsupported, resolveToolbarSlot(it)) }
        // Unknown -> automatic (trailing).
        assertEquals(ToolbarSlot.Trailing, resolveToolbarSlot("madeUp"))
    }

    private fun toolbarItem(placement: String, contentId: Int) = ActionUIElement(
        type = "ToolbarItem",
        properties = buildJsonObject { put("placement", placement) },
        content = ActionUIElement(id = contentId, type = "Button"),
    )

    @Test
    fun `resolveToolbar buckets items and flattens groups`() {
        val logger = CapturingLogger()
        val element = ActionUIElement(
            id = 1, type = "VStack",
            toolbar = listOf(
                toolbarItem("topBarLeading", 1),
                ActionUIElement(
                    type = "ToolbarItemGroup",
                    properties = buildJsonObject { put("placement", "topBarTrailing") },
                    children = listOf(
                        ActionUIElement(id = 2, type = "Button"),
                        ActionUIElement(id = 3, type = "Button"),
                    ),
                ),
                toolbarItem("secondaryAction", 4),
                toolbarItem("bottomBar", 5),
            ),
        )
        val buckets = resolveToolbar(element, logger)

        assertEquals(listOf(1), buckets.leading.map { it.id })
        assertEquals(listOf(2, 3), buckets.trailing.map { it.id })
        assertEquals(listOf(4), buckets.overflow.map { it.id })
        assertEquals(listOf(5), buckets.bottom.map { it.id })
        assertTrue(buckets.principal.isEmpty())
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveToolbar drops an unsupported placement with a warning`() {
        val logger = CapturingLogger()
        val element = ActionUIElement(
            id = 1, type = "VStack",
            toolbar = listOf(toolbarItem("keyboard", 9)),
        )
        val buckets = resolveToolbar(element, logger)

        assertTrue(buckets.trailing.isEmpty() && buckets.bottom.isEmpty() && buckets.overflow.isEmpty())
        assertTrue(logger.warnings.any { it.contains("keyboard") })
    }

    @Test
    fun `no toolbar yields empty buckets`() {
        val buckets = resolveToolbar(ActionUIElement(id = 1, type = "VStack"), CapturingLogger())
        assertTrue(
            buckets.leading.isEmpty() && buckets.principal.isEmpty() && buckets.trailing.isEmpty() &&
                buckets.overflow.isEmpty() && buckets.bottom.isEmpty(),
        )
    }

    @Test
    fun `hasRootToolbarChrome detects a root toolbar or navigationTitle`() {
        // A plain root view with a toolbar -> wrapped as a screen.
        assertTrue(
            hasRootToolbarChrome(
                ActionUIElement(id = 1, type = "List", toolbar = listOf(toolbarItem("topBarLeading", 1))),
            ),
        )
        // navigationTitle alone is enough (renders as the bar title).
        assertTrue(
            hasRootToolbarChrome(
                ActionUIElement(
                    id = 1, type = "VStack",
                    properties = buildJsonObject { put("navigationTitle", "Inbox") },
                ),
            ),
        )
        // No chrome -> rendered bare.
        assertFalse(hasRootToolbarChrome(ActionUIElement(id = 1, type = "VStack")))
    }

    @Test
    fun `hasRootToolbarChrome excludes NavigationStack (owns its own per-screen host)`() {
        assertFalse(
            hasRootToolbarChrome(
                ActionUIElement(
                    id = 1, type = "NavigationStack",
                    properties = buildJsonObject { put("navigationTitle", "Inbox") },
                    toolbar = listOf(toolbarItem("topBarLeading", 1)),
                ),
            ),
        )
    }
}
