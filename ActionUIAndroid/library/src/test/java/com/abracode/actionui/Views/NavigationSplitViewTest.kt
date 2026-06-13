package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [NavigationSplitView] - registry resolution, the
 * `selectedDestination` / `columnVisibility` state seeds, the pure
 * [navigationSplitDestinations] (detail targets keyed by id, id-0 skipped), and the
 * pure [resolveSplitColumnVisibility] / [resolveSplitStyle] property maps. The
 * `@Composable` `NavigableListDetailPaneScaffold` / pane / selection surfaces are
 * exercised by the app (it needs a window size class to lay out).
 */
class NavigationSplitViewTest {

    @Test
    fun `NavigationSplitView resolves in the registry`() {
        assertSame(NavigationSplitView, ActionUIRegistry.lookup("NavigationSplitView"))
    }

    @Test
    fun `seeds selectedDestination and columnVisibility to defaults`() {
        assertEquals(
            mapOf("selectedDestination" to 0, "columnVisibility" to "all"),
            NavigationSplitView.initialStates(ActionUIElement(id = 1, type = "NavigationSplitView")),
        )
    }

    @Test
    fun `seeds columnVisibility from the author property`() {
        val element = ActionUIElement(
            id = 1, type = "NavigationSplitView",
            properties = buildJsonObject { put("columnVisibility", "detail") },
        )
        assertEquals("detail", NavigationSplitView.initialStates(element)["columnVisibility"])
    }

    @Test
    fun `resolveSplitColumnVisibility maps known values and defaults to all`() {
        assertEquals(SplitColumnVisibility.Automatic, resolveSplitColumnVisibility("automatic"))
        assertEquals(SplitColumnVisibility.DoubleColumn, resolveSplitColumnVisibility("doubleColumn"))
        assertEquals(SplitColumnVisibility.Detail, resolveSplitColumnVisibility("detail"))
        assertEquals(SplitColumnVisibility.All, resolveSplitColumnVisibility("all"))
        assertEquals(SplitColumnVisibility.All, resolveSplitColumnVisibility(null))
        assertEquals(SplitColumnVisibility.All, resolveSplitColumnVisibility("bogus"))
    }

    @Test
    fun `resolveSplitStyle maps known values and defaults to automatic`() {
        assertEquals(SplitStyle.Balanced, resolveSplitStyle("balanced"))
        assertEquals(SplitStyle.ProminentDetail, resolveSplitStyle("prominentDetail"))
        assertEquals(SplitStyle.Automatic, resolveSplitStyle("automatic"))
        assertEquals(SplitStyle.Automatic, resolveSplitStyle(null))
        assertEquals(SplitStyle.Automatic, resolveSplitStyle("bogus"))
    }

    @Test
    fun `navigationSplitDestinations keys destinations by id`() {
        val element = ActionUIElement(
            id = 1, type = "NavigationSplitView",
            destinations = listOf(
                ActionUIElement(id = 10, type = "VStack"),
                ActionUIElement(id = 11, type = "VStack"),
            ),
        )
        val map = navigationSplitDestinations(element)

        assertEquals(setOf(10, 11), map.keys)
        assertEquals("VStack", map[10]?.type)
    }

    @Test
    fun `isSidebarRowSelected highlights only the matching destination row`() {
        // The row linked to the current selection is highlighted...
        assertTrue(isSidebarRowSelected(destId = 11, selected = 11))
        // ...a row linked to a different destination is not...
        assertFalse(isSidebarRowSelected(destId = 10, selected = 11))
        // ...and a row with no destinationViewId (a static header/spacer) never is,
        // even when its id would coincide with the selection sentinel.
        assertFalse(isSidebarRowSelected(destId = null, selected = 0))
        assertFalse(isSidebarRowSelected(destId = null, selected = 11))
    }

    @Test
    fun `navigationSplitDestinations skips id-0 and is empty without destinations`() {
        val withZero = ActionUIElement(
            id = 1, type = "NavigationSplitView",
            destinations = listOf(ActionUIElement(id = 0, type = "VStack")),
        )
        assertTrue(navigationSplitDestinations(withZero).isEmpty())
        assertTrue(navigationSplitDestinations(ActionUIElement(id = 1, type = "NavigationSplitView")).isEmpty())
    }
}
