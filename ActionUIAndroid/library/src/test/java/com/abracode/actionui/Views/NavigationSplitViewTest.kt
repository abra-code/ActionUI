package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [NavigationSplitView] - registry resolution, the
 * `selectedDestination` state seed, and the pure [navigationSplitDestinations]
 * (detail targets keyed by id, id-0 skipped). The `@Composable`
 * `NavigableListDetailPaneScaffold` / pane / selection surfaces are exercised by
 * the app (it needs a window size class to lay out).
 */
class NavigationSplitViewTest {

    @Test
    fun `NavigationSplitView resolves in the registry`() {
        assertSame(NavigationSplitView, ActionUIRegistry.lookup("NavigationSplitView"))
    }

    @Test
    fun `seeds selectedDestination to none`() {
        assertEquals(
            mapOf("selectedDestination" to 0),
            NavigationSplitView.initialStates(ActionUIElement(id = 1, type = "NavigationSplitView")),
        )
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
    fun `navigationSplitDestinations skips id-0 and is empty without destinations`() {
        val withZero = ActionUIElement(
            id = 1, type = "NavigationSplitView",
            destinations = listOf(ActionUIElement(id = 0, type = "VStack")),
        )
        assertTrue(navigationSplitDestinations(withZero).isEmpty())
        assertTrue(navigationSplitDestinations(ActionUIElement(id = 1, type = "NavigationSplitView")).isEmpty())
    }
}
