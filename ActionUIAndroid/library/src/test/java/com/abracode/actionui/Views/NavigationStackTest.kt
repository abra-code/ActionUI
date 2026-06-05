package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [NavigationStack] - registry resolution, the navigationPath
 * state seed, and the pure [buildDestinationMap] (explicit destinations, inline
 * hoisting, explicit-wins precedence, and the id-0 skip). The `@Composable`
 * NavHost / push / back-stack sync surfaces are exercised by the app.
 */
class NavigationStackTest {

    @Test
    fun `NavigationStack resolves in the registry`() {
        assertSame(NavigationStack, ActionUIRegistry.lookup("NavigationStack"))
    }

    @Test
    fun `seeds an empty navigation path`() {
        assertEquals(
            mapOf("navigationPath" to emptyList<Int>()),
            NavigationStack.initialStates(ActionUIElement(id = 1, type = "NavigationStack")),
        )
    }

    @Test
    fun `buildDestinationMap keys explicit destinations by id`() {
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            destinations = listOf(
                ActionUIElement(id = 10, type = "Text"),
                ActionUIElement(id = 11, type = "Text"),
            ),
        )
        val map = buildDestinationMap(stack)
        assertEquals(setOf(10, 11), map.keys)
        assertEquals("Text", map[10]?.type)
    }

    @Test
    fun `buildDestinationMap hoists inline destinations from the content subtree`() {
        // A NavigationLink with an inline destination, nested under content.
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            content = ActionUIElement(
                id = 2, type = "VStack",
                children = listOf(
                    ActionUIElement(
                        id = 3, type = "NavigationLink",
                        destination = ActionUIElement(id = 99, type = "Text"),
                    ),
                ),
            ),
        )
        val map = buildDestinationMap(stack)
        assertEquals(setOf(99), map.keys)
        assertEquals(99, map[99]?.id)
    }

    @Test
    fun `explicit destinations win over an inline destination sharing an id`() {
        val explicit = ActionUIElement(id = 10, type = "VStack")
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            content = ActionUIElement(
                id = 2, type = "NavigationLink",
                destination = ActionUIElement(id = 10, type = "Text"), // same id, inline
            ),
            destinations = listOf(explicit),
        )
        assertSame(explicit, buildDestinationMap(stack)[10])
    }

    @Test
    fun `inline destinations without an id are not addressable`() {
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            content = ActionUIElement(
                id = 2, type = "NavigationLink",
                destination = ActionUIElement(type = "Text"), // id defaults to 0
            ),
        )
        assertNull(buildDestinationMap(stack)[0])
        assertEquals(emptyMap<Int, ActionUIElement>(), buildDestinationMap(stack))
    }
}
