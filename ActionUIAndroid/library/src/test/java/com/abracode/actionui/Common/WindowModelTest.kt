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
    fun `display and container elements get no seeded value`() {
        val root = ActionUIElement(
            id = 1, type = "VStack",
            children = listOf(ActionUIElement(id = 2, type = "Text"))
        )
        val window = model()
        window.loadDescription(root)

        assertNull(window.viewModels[1]?.value)
        assertNull(window.viewModels[2]?.value)
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
}
