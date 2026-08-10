package com.abracode.actionui.Common

import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [WindowModel.populateViewModels] (exercised via
 * [WindowModel.loadDescription]): one [ViewModel] per element id, `elementType`
 * captured, and value-bearing elements seeded with their initial value while
 * display/container elements are not.
 *
 * The Compose snapshot-state fields ([ViewModel.value] / [ViewModel.states]) are
 * read/written here as plain values - the snapshot machinery works on the JVM
 * without a composition, which is what makes this model layer unit-testable.
 */
class WindowModelTest {

    private fun model(): WindowModel = WindowModel(windowUUID = "", logger = ConsoleLogger())

    @Test
    fun `populates one view model per element keyed by id with element type`() {
        val root = ActionUIElement(
            id = 1, type = "VStack",
            children = listOf(
                ActionUIElement(id = 2, type = "Text"),
                ActionUIElement(id = 3, type = "TextField"),
            )
        )
        val window = model()
        window.loadDescription(root)

        assertEquals(3, window.viewModels.size)
        assertEquals("VStack", window.viewModels[1]?.elementType)
        assertEquals("Text", window.viewModels[2]?.elementType)
        assertEquals("TextField", window.viewModels[3]?.elementType)
    }

    @Test
    fun `seeds initial value for value-bearing element from text property`() {
        val root = ActionUIElement(
            id = 1, type = "TextField",
            properties = buildJsonObject { put("text", "hello") }
        )
        val window = model()
        window.loadDescription(root)

        assertEquals("hello", window.viewModels[1]?.value)
    }

    @Test
    fun `secure field honors text but not value fallback`() {
        val root = ActionUIElement(
            id = 1, type = "SecureField",
            properties = buildJsonObject { put("value", "9.99") } // no "text"
        )
        val window = model()
        window.loadDescription(root)

        // Secure fields only honor "text"; the numeric "value" fallback is plain-only.
        assertEquals("", window.viewModels[1]?.value)
    }

    @Test
    fun `valueless display and container elements get no seeded value`() {
        // A container (VStack) and a genuinely valueless display leaf (Spacer)
        // are NONE-typed and seed no value. (Text is no longer in this set: it
        // is now value-bearing, STRING, for value-bridge parity with SwiftUI.)
        val root = ActionUIElement(
            id = 1, type = "VStack",
            children = listOf(ActionUIElement(id = 2, type = "Spacer"))
        )
        val window = model()
        window.loadDescription(root)

        assertNull(window.viewModels[1]?.value)
        assertNull(window.viewModels[2]?.value)
    }

    @Test
    fun `value-bearing display elements seed from their content property`() {
        // Text and Label became value-bearing (STRING) for SwiftUI parity: their
        // displayed content is the seeded ViewModel value, host-addressable by id.
        val root = ActionUIElement(
            id = 1, type = "VStack",
            children = listOf(
                ActionUIElement(id = 2, type = "Text",
                    properties = buildJsonObject { put("text", "hello") }),
                ActionUIElement(id = 3, type = "Label",
                    properties = buildJsonObject { put("title", "Favorites") }),
            )
        )
        val window = model()
        window.loadDescription(root)

        assertEquals("hello", window.viewModels[2]?.value)
        assertEquals("Favorites", window.viewModels[3]?.value)
    }

    @Test
    fun `descends into the single-child content container`() {
        // A value-bearing control nested under `content` (e.g. inside a
        // ScrollView) must be registered and seeded, just like one under
        // `children`, so the host can address it by id.
        val root = ActionUIElement(
            id = 1, type = "ScrollView",
            content = ActionUIElement(
                id = 2, type = "TextField",
                properties = buildJsonObject { put("text", "scrolled") }
            )
        )
        val window = model()
        window.loadDescription(root)

        assertEquals(2, window.viewModels.size)
        assertEquals("ScrollView", window.viewModels[1]?.elementType)
        assertEquals("scrolled", window.viewModels[2]?.value)
    }

    @Test
    fun `seeds initial states from the builder`() {
        // DisclosureGroup seeds states["isExpanded"] via initialStates, so the
        // state is host-addressable before any interaction.
        val root = ActionUIElement(
            id = 1, type = "DisclosureGroup",
            properties = buildJsonObject { put("isExpanded", true) }
        )
        val window = model()
        window.loadDescription(root)

        assertEquals(true, window.viewModels[1]?.states?.get("isExpanded"))
    }

    @Test
    fun `template container is not registered in the view model pool`() {
        // Template instances are per-row throw-aways; their elements must not be
        // seeded into the window pool (subElements excludes template).
        val root = ActionUIElement(
            id = 1, type = "List",
            template = ActionUIElement(id = 99, type = "Text"),
        )
        val window = model()
        window.loadDescription(root)

        assertEquals(1, window.viewModels.size)
        assertTrue(window.viewModels.containsKey(1))
        assertNull(window.viewModels[99])
    }

    @Test
    fun `descends into the navigation destination and destinations containers`() {
        // A NavigationStack's destinations (and a link's inline destination) must
        // be registered so their controls are host-addressable by id.
        val root = ActionUIElement(
            id = 1, type = "NavigationStack",
            content = ActionUIElement(
                id = 2, type = "NavigationLink",
                destination = ActionUIElement(id = 3, type = "TextField",
                    properties = buildJsonObject { put("text", "inline") }),
            ),
            destinations = listOf(
                ActionUIElement(id = 10, type = "TextField",
                    properties = buildJsonObject { put("text", "dest") }),
            ),
        )
        val window = model()
        window.loadDescription(root)

        assertEquals(4, window.viewModels.size)
        assertEquals("inline", window.viewModels[3]?.value)
        assertEquals("dest", window.viewModels[10]?.value)
    }

    @Test
    fun `descends into TabView tab content`() {
        // A TabView's tabs (children) and each tab's content must register so the
        // host can address controls inside a tab by id.
        val root = ActionUIElement(
            id = 1, type = "TabView",
            children = listOf(
                ActionUIElement(
                    id = 2, type = "Tab",
                    content = ActionUIElement(id = 3, type = "TextField",
                        properties = buildJsonObject { put("text", "tabbed") }),
                ),
            ),
        )
        val window = model()
        window.loadDescription(root)

        assertEquals("tabbed", window.viewModels[3]?.value)
        // TabView is INT-valued: its selection is seeded.
        assertEquals(0, window.viewModels[1]?.value)
    }

    @Test
    fun `descends into toolbar item content and group children`() {
        // Toolbar items are consumed by the chrome, but their content/children must
        // register so a host can address a toolbar control by id.
        val root = ActionUIElement(
            id = 1, type = "VStack",
            toolbar = listOf(
                ActionUIElement(id = 2, type = "ToolbarItem",
                    content = ActionUIElement(id = 3, type = "TextField",
                        properties = buildJsonObject { put("text", "item") })),
                ActionUIElement(id = 4, type = "ToolbarItemGroup",
                    children = listOf(ActionUIElement(id = 5, type = "TextField",
                        properties = buildJsonObject { put("text", "grp") }))),
            ),
        )
        val window = model()
        window.loadDescription(root)

        assertEquals("item", window.viewModels[3]?.value)
        assertEquals("grp", window.viewModels[5]?.value)
    }

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun toolbarItem(contentId: Int, text: String) = ActionUIElement(
        type = "ToolbarItem",
        content = ActionUIElement(
            id = contentId, type = "TextField",
            properties = buildJsonObject { put("text", text) },
        ),
    )

    @Test
    fun `descends into persistentToolbar item content`() {
        // Same contract as `toolbar`: the items are consumed by the chrome, but their
        // content must register so a host can address a persistent control by id - and so
        // `hidden` on one works, which is the only per-screen opt-out this feature has.
        val root = ActionUIElement(
            id = 1, type = "NavigationStack",
            persistentToolbar = listOf(toolbarItem(3, "pers")),
        )
        val window = model()
        window.loadDescription(root)

        assertEquals("pers", window.viewModels[3]?.value)
    }

    @Test
    fun `warns once when a navigation container carries the deprecated toolbar alias`() {
        val logger = CapturingLogger()
        val window = WindowModel(windowUUID = "W", logger = logger)
        window.loadDescription(
            ActionUIElement(id = 1, type = "NavigationStack", toolbar = listOf(toolbarItem(3, "alias"))),
        )

        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("Deprecated"))
        assertTrue(logger.warnings[0].contains("NavigationStack"))
        assertTrue(logger.warnings[0].contains("persistentToolbar"))
    }

    @Test
    fun `warns when persistentToolbar is declared somewhere that cannot render it`() {
        // The opposite mistake, and the silent one: only the two containers read the key,
        // so anywhere else the items decode, get view models, and render nothing at all.
        val logger = CapturingLogger()
        val window = WindowModel(windowUUID = "W", logger = logger)
        window.loadDescription(
            ActionUIElement(id = 1, type = "VStack", persistentToolbar = listOf(toolbarItem(3, "lost"))),
        )

        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("ignored"))
        assertTrue(logger.warnings[0].contains("VStack"))
    }

    @Test
    fun `the two persistentToolbar warnings stay quiet on correct documents`() {
        val logger = CapturingLogger()
        val window = WindowModel(windowUUID = "W", logger = logger)
        window.loadDescription(
            ActionUIElement(
                id = 1, type = "NavigationStack",
                persistentToolbar = listOf(toolbarItem(3, "pers")),
                content = ActionUIElement(id = 2, type = "VStack", toolbar = listOf(toolbarItem(4, "screen"))),
            ),
        )

        assertTrue(logger.warnings.toString(), logger.warnings.isEmpty())
    }

    @Test
    fun `NavigationStack seeds an empty navigation path state`() {
        val window = model()
        window.loadDescription(ActionUIElement(id = 1, type = "NavigationStack"))

        assertEquals(emptyList<Int>(), window.viewModels[1]?.states?.get("navigationPath"))
    }

    @Test
    fun `List seeds empty rows in its content state`() {
        val window = model()
        window.loadDescription(ActionUIElement(id = 1, type = "List"))

        assertEquals(emptyList<List<String>>(), window.viewModels[1]?.states?.get("content"))
    }

    @Test
    fun `loadSubDescription merges into the pool without clearing it`() {
        // A LoadableView's loaded sub-tree registers into the SAME window so the
        // value API reaches its controls by id; the original pool stays intact.
        val window = model()
        window.loadDescription(
            ActionUIElement(
                id = 1, type = "VStack",
                children = listOf(
                    ActionUIElement(id = 2, type = "LoadableView",
                        properties = buildJsonObject { put("name", "Sub.json") }),
                ),
            )
        )
        assertEquals(2, window.viewModels.size)

        window.loadSubDescription(
            ActionUIElement(
                id = 10, type = "VStack",
                children = listOf(
                    ActionUIElement(id = 11, type = "TextField",
                        properties = buildJsonObject { put("text", "loaded") }),
                ),
            )
        )

        // Original ids survive; the merged sub-tree's controls are addressable.
        assertEquals(4, window.viewModels.size)
        assertEquals("LoadableView", window.viewModels[2]?.elementType)
        assertEquals("loaded", window.viewModels[11]?.value)
        // The window root is unchanged (still the original document).
        assertEquals(1, window.element?.id)
    }

    @Test
    fun `id-less elements are not registered and cannot cross-wire`() {
        // Elements without an id default to 0; registering them would collide
        // on one map key, last-one-wins, so every id-less value control in the
        // document would bind to the same ViewModel and read the LAST one's
        // seeded value (three id-less AsyncImages all loading the last url -
        // the entry-49 demo regression). Id-less elements must not register.
        val root = ActionUIElement(
            type = "VStack",
            children = listOf(
                ActionUIElement(type = "AsyncImage",
                    properties = buildJsonObject { put("url", "https://example.com/a.png") }),
                ActionUIElement(type = "AsyncImage",
                    properties = buildJsonObject { put("url", "invalid-url") }),
                ActionUIElement(id = 5, type = "TextField",
                    properties = buildJsonObject { put("text", "kept") }),
            )
        )
        val window = model()
        window.loadDescription(root)

        assertEquals(1, window.viewModels.size)
        assertNull(window.viewModels[0])
        assertEquals("kept", window.viewModels[5]?.value)
    }

    @Test
    fun `reloading rebuilds the pool from the new element`() {
        val window = model()
        window.loadDescription(
            ActionUIElement(id = 1, type = "TextField", properties = buildJsonObject { put("text", "a") })
        )
        window.loadDescription(ActionUIElement(id = 9, type = "Text"))

        assertEquals(1, window.viewModels.size)
        assertTrue(window.viewModels.containsKey(9))
        assertNull(window.viewModels[1])
    }

    @Test
    fun `descends into the overlay and background decoration subviews`() {
        // Decoration content must register so a host can address it by id -
        // e.g. a dismiss Button overlaid on a card.
        val root = ActionUIElement(
            id = 1, type = "Rectangle",
            overlay = ActionUIElement(
                id = 2, type = "ZStack",
                children = listOf(ActionUIElement(id = 3, type = "TextField",
                    properties = buildJsonObject { put("text", "badge") })),
            ),
            background = ActionUIElement(id = 4, type = "Capsule"),
        )
        val window = model()
        window.loadDescription(root)

        assertEquals("badge", window.viewModels[3]?.value)
        assertEquals("Capsule", window.viewModels[4]?.elementType)
    }
}
