package com.abracode.actionui.Common

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for the data-driven rows API on [ActionUIModel]
 * (`get/set/append/clearElementRows`, `getElementColumnCount`). The rows live in
 * `states[`[ActionUIModel.ROWS_STATE_KEY]`]`; the snapshot-state machinery works
 * on the JVM without a composition, which is what makes this unit-testable.
 */
class ActionUIModelRowsTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    private fun loadList() {
        // A List seeds states["content"] = [] via initialStates.
        ActionUIModel.loadDescription(ActionUIElement(id = 1, type = "List"), windowUUID = "")
    }

    private val planets = listOf(
        listOf("Mercury", "rocky"),
        listOf("Jupiter", "gas"),
    )

    @Test
    fun `seeded rows start empty`() {
        loadList()
        assertEquals(emptyList<List<String>>(), ActionUIModel.getElementRows(viewID = 1))
        assertEquals(0, ActionUIModel.getElementColumnCount(viewID = 1))
    }

    @Test
    fun `set then get round-trips the rows`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = planets)
        assertEquals(planets, ActionUIModel.getElementRows(viewID = 1))
    }

    @Test
    fun `append adds after existing rows`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = planets)
        ActionUIModel.appendElementRows(viewID = 1, rows = listOf(listOf("Mars", "rocky")))
        assertEquals(planets + listOf(listOf("Mars", "rocky")), ActionUIModel.getElementRows(viewID = 1))
    }

    @Test
    fun `clear empties the rows`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = planets)
        ActionUIModel.clearElementRows(viewID = 1)
        assertEquals(emptyList<List<String>>(), ActionUIModel.getElementRows(viewID = 1))
    }

    @Test
    fun `column count is the widest row`() {
        loadList()
        ActionUIModel.setElementRows(
            viewID = 1,
            rows = listOf(listOf("a"), listOf("b", "c", "d"), listOf("e", "f")),
        )
        assertEquals(3, ActionUIModel.getElementColumnCount(viewID = 1))
    }

    @Test
    fun `unknown id yields empty rows and set is a no-op`() {
        loadList()
        assertEquals(emptyList<List<String>>(), ActionUIModel.getElementRows(viewID = 404))
        ActionUIModel.setElementRows(viewID = 404, rows = planets) // no crash, no effect
        assertEquals(emptyList<List<String>>(), ActionUIModel.getElementRows(viewID = 404))
    }
}
