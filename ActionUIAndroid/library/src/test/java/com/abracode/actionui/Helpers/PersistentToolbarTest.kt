package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.subElements
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the `persistentToolbar` key: the pure functions that decide WHICH items
 * belong to a container and which belong to a screen, and the merge that puts both in one
 * bar. See `Private/Design-36-Persistent-Toolbar.md` section 6.
 *
 * The `@Composable` half - the container publishing through [LocalPersistentToolbarItems],
 * each screen merging what it finds, and the decision of WHETHER a screen gets a bar at
 * all - is exercised by the demo app (`NavigationStack.persistentToolbar.json`), as the
 * rest of the Compose layer is. What is covered here is which items belong to a container
 * versus a screen, and how the two merge once a bar exists. The split view's per-pane rule
 * is pure and tested separately, in `Views/NavigationSplitViewTest.kt`.
 */
class PersistentToolbarTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun item(placement: String, contentId: Int, title: String) = ActionUIElement(
        type = "ToolbarItem",
        properties = buildJsonObject { put("placement", placement) },
        content = ActionUIElement(
            id = contentId,
            type = "Button",
            properties = buildJsonObject { put("title", title) },
        ),
    )

    @Test
    fun `isNavigationContainer covers both containers and nothing else`() {
        assertTrue(isNavigationContainer("NavigationStack"))
        assertTrue(isNavigationContainer("NavigationSplitView"))
        // NavigationLink pushes a screen, it does not own a navigation context.
        listOf("VStack", "List", "NavigationLink", "TabView", "")
            .forEach { assertFalse(it, isNavigationContainer(it)) }
    }

    @Test
    fun `persistentToolbarItems reads the persistentToolbar array`() {
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            persistentToolbar = listOf(item("topBarTrailing", 61, "PERS")),
        )
        assertEquals(listOf(61), persistentToolbarItems(stack).map { it.content?.id })
    }

    @Test
    fun `persistentToolbarItems reads a container's toolbar as the deprecated alias`() {
        // The whole point of the alias: a container-level `toolbar` was never a screen
        // toolbar on any host - Android simply never read it - so it means this now.
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            toolbar = listOf(item("topBarTrailing", 11, "ALIAS")),
        )
        assertEquals(listOf(11), persistentToolbarItems(stack).map { it.content?.id })
    }

    @Test
    fun `persistentToolbarItems takes both keys, persistent first`() {
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            persistentToolbar = listOf(item("topBarTrailing", 61, "PERS")),
            toolbar = listOf(item("topBarTrailing", 11, "ALIAS")),
        )
        assertEquals(listOf(61, 11), persistentToolbarItems(stack).map { it.content?.id })
    }

    @Test
    fun `screenToolbarItems returns an ordinary element's own toolbar`() {
        val screen = ActionUIElement(
            id = 2, type = "VStack",
            toolbar = listOf(item("topBarLeading", 21, "ROOT")),
        )
        assertEquals(listOf(21), screenToolbarItems(screen).map { it.content?.id })
    }

    @Test
    fun `screenToolbarItems is empty for a navigation container`() {
        // The double-application guard. A nested NavigationStack used as a destination
        // declares container items; treating them as the parent screen's toolbar would
        // render them once outside the inner stack and again on every screen inside it.
        val nested = ActionUIElement(
            id = 5, type = "NavigationStack",
            toolbar = listOf(item("topBarTrailing", 51, "INNER")),
            persistentToolbar = listOf(item("topBarTrailing", 52, "INNER2")),
        )
        assertTrue(screenToolbarItems(nested).isEmpty())
        // ... and they are still readable as CONTAINER items, which is where they belong.
        assertEquals(listOf(52, 51), persistentToolbarItems(nested).map { it.content?.id })
    }

    @Test
    fun `resolveToolbar puts the persistent items after the screen's own in the same slot`() {
        // One bar, not two, and the persistent item keeps the outer edge as screens change.
        val logger = CapturingLogger()
        val screen = ActionUIElement(
            id = 2, type = "VStack",
            toolbar = listOf(item("topBarTrailing", 41, "DSTA")),
        )
        val buckets = resolveToolbar(screen, logger, listOf(item("topBarTrailing", 61, "PERS")))

        assertEquals(listOf(41, 61), buckets.trailing.map { it.id })
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveToolbar fills a slot for a screen that declares no toolbar of its own`() {
        // The behavior the feature exists for. Whether such a screen gets a bar AT ALL is
        // decided by RenderNavChild / PaneChrome, which are @Composable and not covered
        // here; this pins that the items reach the bucket once the bar exists.
        val logger = CapturingLogger()
        val bare = ActionUIElement(id = 600, type = "VStack")
        val buckets = resolveToolbar(bare, logger, listOf(item("topBarTrailing", 61, "PERS")))

        assertEquals(listOf(61), buckets.trailing.map { it.id })
    }

    @Test
    fun `resolveToolbar keeps persistent items in their own authored slots`() {
        val logger = CapturingLogger()
        val screen = ActionUIElement(
            id = 2, type = "VStack",
            toolbar = listOf(item("topBarTrailing", 41, "DSTA")),
        )
        val buckets = resolveToolbar(
            screen,
            logger,
            listOf(item("topBarLeading", 62, "PL"), item("bottomBar", 63, "PB")),
        )

        assertEquals(listOf(62), buckets.leading.map { it.id })
        assertEquals(listOf(41), buckets.trailing.map { it.id })
        assertEquals(listOf(63), buckets.bottom.map { it.id })
    }

    @Test
    fun `resolveToolbar ignores a nested container's own toolbar as a screen toolbar`() {
        // resolveToolbar reads the screen's items through screenToolbarItems, so the guard
        // holds at the merge site and not only where callers remember to apply it.
        val logger = CapturingLogger()
        val nested = ActionUIElement(
            id = 5, type = "NavigationStack",
            toolbar = listOf(item("topBarTrailing", 51, "INNER")),
        )
        val buckets = resolveToolbar(nested, logger, listOf(item("topBarTrailing", 61, "PERS")))

        assertEquals(listOf(61), buckets.trailing.map { it.id })
    }

    @Test
    fun `persistentToolbar members are part of the element tree`() {
        // subElements is Android's single traversal: omit the container here and the items
        // decode, sit in the tree, and never get a ViewModel - so a host could not address
        // them and `hidden` on one would do nothing. Silent, hence the test.
        val stack = ActionUIElement(
            id = 1, type = "NavigationStack",
            persistentToolbar = listOf(item("topBarTrailing", 61, "PERS")),
        )
        assertEquals(listOf("ToolbarItem"), stack.subElements().map { it.type })
    }
}
