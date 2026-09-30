package com.abracode.actionui.Common

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for the programmatic row-selection API on [ActionUIModel]
 * (`selectElementRow` by index / by content, `clearElementSelection`). Selection is
 * stored in [ViewModel.value] (read back via `getElementValue`) without altering the
 * rows in `states[`[ActionUIModel.ROWS_STATE_KEY]`]`. Mirrors the Swift `TableTests`.
 */
class ActionUIModelSelectionTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    private fun loadList() {
        ActionUIModel.loadDescription(ActionUIElement(id = 1, type = "List"), windowUUID = "")
    }

    private val rows = listOf(
        listOf("Alice", "30"),
        listOf("Bob", "25"),
        listOf("Carol", "40"),
    )

    @Test
    fun `select by index sets the value and leaves rows untouched`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        val selected = ActionUIModel.selectElementRow(viewID = 1, index = 1)
        assertEquals(listOf("Bob", "25"), selected)
        assertEquals(listOf("Bob", "25"), ActionUIModel.getElementValue(viewID = 1))
        assertEquals(rows, ActionUIModel.getElementRows(viewID = 1))
    }

    @Test
    fun `out-of-range index clears the selection`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        ActionUIModel.selectElementRow(viewID = 1, index = 0)
        assertNull(ActionUIModel.selectElementRow(viewID = 1, index = 99))
        assertEquals(emptyList<String>(), ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `select by content matches any column`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        assertEquals(1, ActionUIModel.selectElementRow(viewID = 1, text = "25"))
        assertEquals(listOf("Bob", "25"), ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `select by content matches a specific column`() {
        loadList()
        // "30" appears in column 1 of row 0 and as a name in column 0 of row 2
        ActionUIModel.setElementRows(viewID = 1, rows = listOf(
            listOf("Alice", "30"), listOf("Bob", "25"), listOf("30", "99"),
        ))
        assertEquals(0, ActionUIModel.selectElementRow(viewID = 1, text = "30", column = 1))
        assertEquals(2, ActionUIModel.selectElementRow(viewID = 1, text = "30", column = 0))
    }

    @Test
    fun `no content match leaves the existing selection`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        ActionUIModel.selectElementRow(viewID = 1, index = 0)
        assertNull(ActionUIModel.selectElementRow(viewID = 1, text = "nope"))
        assertEquals(listOf("Alice", "30"), ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `clear selection empties the value`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        ActionUIModel.selectElementRow(viewID = 1, index = 1)
        ActionUIModel.clearElementSelection(viewID = 1)
        assertEquals(emptyList<String>(), ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `a rows change to another column keeps the row selected with its new columns`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        ActionUIModel.selectElementRow(viewID = 1, index = 1)
        ActionUIModel.setElementRows(viewID = 1, rows = listOf(listOf("Bob", "26"), listOf("Alice", "30")))
        assertEquals(listOf("Bob", "26"), ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `a rows change keeps an identical row over an earlier one with the same first column`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = listOf(listOf("Alice", "30"), listOf("Alice", "40")))
        ActionUIModel.selectElementRow(viewID = 1, index = 1)
        ActionUIModel.setElementRows(viewID = 1, rows = listOf(listOf("Alice", "30"), listOf("Alice", "40"), listOf("Bob", "25")))
        assertEquals(listOf("Alice", "40"), ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `a rows change that drops the selected row clears the selection`() {
        loadList()
        ActionUIModel.setElementRows(viewID = 1, rows = rows)
        ActionUIModel.selectElementRow(viewID = 1, index = 2)
        ActionUIModel.setElementRows(viewID = 1, rows = rows.take(2))
        assertEquals(emptyList<String>(), ActionUIModel.getElementValue(viewID = 1))
        ActionUIModel.selectElementRow(viewID = 1, index = 0)
        ActionUIModel.clearElementRows(viewID = 1)
        assertEquals(emptyList<String>(), ActionUIModel.getElementValue(viewID = 1))
    }
}
