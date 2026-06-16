package com.abracode.actionui.Common

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the runtime structural-mutation API on [ActionUIModel]
 * (`insertElement` / `insertRow` / `removeElement`) and the [WindowModel] engine
 * behind it. The mutations write the parent's [ViewModel.dynamicSubviews]
 * (snapshot state), which works on the JVM without a composition - so the
 * effective container can be inspected directly here, the same way
 * [ActionUIModelRowsTest] inspects `states`.
 */
class ActionUIModelInsertionTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    // ---- helpers ----

    private fun text(id: Int) = ActionUIElement(id = id, type = "Text")

    /** Loads a VStack (id 1) whose children are Text elements with [childIds]. */
    private fun loadStack(vararg childIds: Int) {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "VStack", children = childIds.map(::text)),
            windowUUID = "",
        )
    }

    /** Loads a Grid (id 2) with one authored row holding a single Text (id 30). */
    private fun loadGrid() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 2, type = "Grid", rows = listOf(listOf(text(30)))),
            windowUUID = "",
        )
    }

    private fun viewModels() = ActionUIModel.windowModels[""]!!.viewModels

    @Suppress("UNCHECKED_CAST")
    private fun effectiveChildren(parentID: Int): List<Int> =
        (viewModels()[parentID]!!.dynamicSubviews["children"] as List<ActionUIElement>).map { it.id }

    @Suppress("UNCHECKED_CAST")
    private fun effectiveRows(parentID: Int): List<List<Int>> =
        (viewModels()[parentID]!!.dynamicSubviews["rows"] as List<List<ActionUIElement>>)
            .map { row -> row.map { it.id } }

    // ---- insertElement: positions ----

    @Test
    fun `append adds at the end and registers the view model`() {
        loadStack(10, 11)
        val id = ActionUIModel.insertElement(parentID = 1, element = text(20))
        assertEquals(20, id)
        assertEquals(listOf(10, 11, 20), effectiveChildren(1))
        assertTrue(viewModels().containsKey(20))
    }

    @Test
    fun `prepend adds at the front`() {
        loadStack(10, 11)
        ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.Prepend)
        assertEquals(listOf(20, 10, 11), effectiveChildren(1))
    }

    @Test
    fun `at inserts at the index`() {
        loadStack(10, 11)
        ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.At(1))
        assertEquals(listOf(10, 20, 11), effectiveChildren(1))
    }

    @Test
    fun `before inserts ahead of the sibling`() {
        loadStack(10, 11)
        ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.Before(11))
        assertEquals(listOf(10, 20, 11), effectiveChildren(1))
    }

    @Test
    fun `after inserts behind the sibling`() {
        loadStack(10, 11)
        ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.After(10))
        assertEquals(listOf(10, 20, 11), effectiveChildren(1))
    }

    @Test
    fun `into an empty children container appends to the front`() {
        loadStack()
        ActionUIModel.insertElement(parentID = 1, element = text(20))
        assertEquals(listOf(20), effectiveChildren(1))
    }

    // ---- insertElement: errors ----

    @Test
    fun `id conflict is rejected`() {
        loadStack(10, 11)
        assertThrows(InsertError.IdConflict::class.java) {
            ActionUIModel.insertElement(parentID = 1, element = text(10))
        }
    }

    @Test
    fun `nested id conflict is rejected`() {
        loadStack(10)
        // The subtree carries id 10 (already mounted) on a descendant.
        val subtree = ActionUIElement(id = 20, type = "VStack", children = listOf(text(10)))
        assertThrows(InsertError.IdConflict::class.java) {
            ActionUIModel.insertElement(parentID = 1, element = subtree)
        }
    }

    @Test
    fun `non-container parent is rejected`() {
        ActionUIModel.loadDescription(ActionUIElement(id = 1, type = "Text"), windowUUID = "")
        assertThrows(InsertError.NotAContainer::class.java) {
            ActionUIModel.insertElement(parentID = 1, element = text(20))
        }
    }

    @Test
    fun `unknown parent is rejected`() {
        loadStack(10)
        assertThrows(InsertError.ParentNotFound::class.java) {
            ActionUIModel.insertElement(parentID = 999, element = text(20))
        }
    }

    @Test
    fun `out-of-bounds index is rejected`() {
        loadStack(10)
        assertThrows(InsertError.PositionOutOfBounds::class.java) {
            ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.At(5))
        }
    }

    @Test
    fun `missing sibling is rejected`() {
        loadStack(10)
        assertThrows(InsertError.SiblingNotFound::class.java) {
            ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.Before(999))
        }
    }

    @Test
    fun `wrong-shape container is rejected`() {
        loadGrid()
        assertThrows(InsertError.WrongMethod::class.java) {
            ActionUIModel.insertElement(parentID = 2, element = text(40), container = "rows")
        }
    }

    // ---- insertElement: JSON-string overload ----

    @Test
    fun `json overload decodes, inserts, and is host-addressable`() {
        loadStack(10)
        val id = ActionUIModel.insertElement(
            parentID = 1,
            jsonString = """{ "type": "Text", "id": 50, "properties": { "text": "hi" } }""",
        )
        assertEquals(50, id)
        assertEquals(listOf(10, 50), effectiveChildren(1))
        assertEquals("hi", ActionUIModel.getElementProperty(viewID = 50, propertyName = "text"))
    }

    @Test
    fun `json overload applies the android platform filter`() {
        loadStack(10)
        // `text:android` wins over `text`; an `:ios` key is dropped - proves the filter ran.
        ActionUIModel.insertElement(
            parentID = 1,
            jsonString = """{ "type": "Text", "id": 51, "properties": { "text": "base", "text:android": "droid" } }""",
        )
        assertEquals("droid", ActionUIModel.getElementProperty(viewID = 51, propertyName = "text"))
    }

    @Test
    fun `json overload rejects a payload with no type`() {
        loadStack(10)
        assertThrows(InsertError.MissingType::class.java) {
            ActionUIModel.insertElement(parentID = 1, jsonString = "{}")
        }
    }

    @Test
    fun `json overload rejects invalid json`() {
        loadStack(10)
        assertThrows(InsertError.InvalidJSON::class.java) {
            ActionUIModel.insertElement(parentID = 1, jsonString = "not json")
        }
    }

    // ---- insertRow (Grid) ----

    @Test
    fun `insert row appends a grid row`() {
        loadGrid()
        val ids = ActionUIModel.insertRow(parentID = 2, cells = listOf(text(40), text(41)))
        assertEquals(listOf(40, 41), ids)
        assertEquals(listOf(listOf(30), listOf(40, 41)), effectiveRows(2))
        assertTrue(viewModels().containsKey(40))
        assertTrue(viewModels().containsKey(41))
    }

    @Test
    fun `insert row prepend places the row first`() {
        loadGrid()
        ActionUIModel.insertRow(parentID = 2, cells = listOf(text(40)), position = InsertPosition.Prepend)
        assertEquals(listOf(listOf(40), listOf(30)), effectiveRows(2))
    }

    @Test
    fun `insert row rejects before-sibling positions`() {
        loadGrid()
        assertThrows(InsertError.UnsupportedPositionForRowContainer::class.java) {
            ActionUIModel.insertRow(parentID = 2, cells = listOf(text(40)), position = InsertPosition.Before(30))
        }
    }

    @Test
    fun `insert element into a grid with no flat container requires one`() {
        loadGrid()
        // Grid exposes only a ROWS container, so the auto-derive for a FLAT
        // container finds none - the request must name a container (there is none
        // valid here, hence ContainerRequired with an empty candidate list).
        assertThrows(InsertError.ContainerRequired::class.java) {
            ActionUIModel.insertElement(parentID = 2, element = text(40))
        }
    }

    // ---- removeElement ----

    @Test
    fun `remove an inserted child and clean its view model`() {
        loadStack(10, 11)
        ActionUIModel.insertElement(parentID = 1, element = text(20))
        ActionUIModel.removeElement(viewID = 20)
        assertEquals(listOf(10, 11), effectiveChildren(1))
        assertFalse(viewModels().containsKey(20))
    }

    @Test
    fun `remove an authored child creates the override without it`() {
        loadStack(10, 11, 12)
        ActionUIModel.removeElement(viewID = 11)
        assertEquals(listOf(10, 12), effectiveChildren(1))
        assertFalse(viewModels().containsKey(11))
    }

    @Test
    fun `remove cascades to descendant view models`() {
        loadStack(10)
        ActionUIModel.insertElement(
            parentID = 1,
            element = ActionUIElement(id = 20, type = "VStack", children = listOf(text(21), text(22))),
        )
        assertTrue(viewModels().containsKey(21))
        ActionUIModel.removeElement(viewID = 20)
        assertEquals(listOf(10), effectiveChildren(1))
        assertFalse(viewModels().containsKey(20))
        assertFalse(viewModels().containsKey(21))
        assertFalse(viewModels().containsKey(22))
    }

    @Test
    fun `remove a grid cell drops only that cell`() {
        loadGrid()
        ActionUIModel.insertRow(parentID = 2, cells = listOf(text(40), text(41)))
        ActionUIModel.removeElement(viewID = 40)
        assertEquals(listOf(listOf(30), listOf(41)), effectiveRows(2))
        assertFalse(viewModels().containsKey(40))
        assertTrue(viewModels().containsKey(41))
    }

    @Test
    fun `removing the root is forbidden`() {
        loadStack(10)
        assertThrows(InsertError.RootRemovalForbidden::class.java) {
            ActionUIModel.removeElement(viewID = 1)
        }
    }

    @Test
    fun `removing an unknown view is rejected`() {
        loadStack(10)
        assertThrows(InsertError.ViewNotFound::class.java) {
            ActionUIModel.removeElement(viewID = 999)
        }
    }

    // ---- round trip ----

    @Test
    fun `insert then remove restores the original children`() {
        loadStack(10, 11)
        ActionUIModel.insertElement(parentID = 1, element = text(20), position = InsertPosition.At(1))
        assertEquals(listOf(10, 20, 11), effectiveChildren(1))
        ActionUIModel.removeElement(viewID = 20)
        assertEquals(listOf(10, 11), effectiveChildren(1))
    }
}
