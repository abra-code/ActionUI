package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ViewModel
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for a `Toggle` whose state is row data, inside a data-driven template:
 * the string-to-Boolean rule, which `isOn` names one column, the write of a user
 * toggle into the container's rows, the action's `viewID` / `viewPartID` / context,
 * that the action fires after the write, that the state is kept across a re-render,
 * and that a selection resting on the toggled row follows it.
 *
 * That a tap on the `Toggle` does not also select its row is Compose's own rule (the
 * inner control consumes the tap, as a `Button` in a row does); it is exercised by
 * the demo app, as the rest of the Compose layer is.
 */
class ToggleRowTest {

    private val packRows = listOf(
        listOf("true", "Xcode and Swift builds", "xcode", "false"),
        listOf("false", "Node", "node", "false"),
        listOf("false", "Locked", "locked", "true"),
    )

    private val toggleTemplate = ActionUIElement(
        type = "Toggle",
        properties = buildJsonObject {
            put("style", "checkbox")
            put("isOn", "$1")
            put("title", "$2")
            put("disabled", "$4")
            put("actionID", "packs.toggled")
        },
    )

    private fun container(rows: List<List<String>> = packRows) = ViewModel().also {
        it.states[ActionUIModel.ROWS_STATE_KEY] = rows
        it.value = emptyList<String>()
    }

    @Suppress("UNCHECKED_CAST")
    private fun rowsOf(container: ViewModel) = container.states[ActionUIModel.ROWS_STATE_KEY] as List<List<String>>

    private fun context(row: Int) = TemplateContext(parentID = 600, rowIndex = row, row = packRows[row])

    @After
    fun tearDown() {
        ActionUIModel.unregisterActionHandler("packs.toggled")
    }

    // ---- The shared rules ----

    @Test
    fun `rowBool reads the documented words in any letter case`() {
        for (text in listOf("true", "TRUE", "True", "1")) assertEquals(text, true, TemplateHelper.rowBool(text))
        for (text in listOf("false", "FALSE", "False", "0", "")) assertEquals(text, false, TemplateHelper.rowBool(text))
        for (text in listOf("yes", "no", "on", " true", "2", "mixed", "\$4")) assertNull(text, TemplateHelper.rowBool(text))
    }

    @Test
    fun `only a whole reference names a column`() {
        assertEquals(0, TemplateHelper.singleColumnIndex(JsonPrimitive("$1")))
        assertEquals(11, TemplateHelper.singleColumnIndex(JsonPrimitive("$12")))
        for (text in listOf("\$0", "\$1 ", "\$1\n", "x\$1", "\$1\$2", "true")) {
            assertNull(text, TemplateHelper.singleColumnIndex(JsonPrimitive(text)))
        }
        assertNull(TemplateHelper.singleColumnIndex(JsonPrimitive(true)))
        assertNull(TemplateHelper.singleColumnIndex(null))
    }

    // ---- Template instance properties ----

    @Test
    fun `isOn and disabled are read from the row`() {
        val first = TemplateHelper.substituteElement(toggleTemplate, packRows[0]).properties!!
        assertEquals(true, first["isOn"]!!.jsonPrimitive.booleanOrNull)
        assertFalse(first["isOn"]!!.jsonPrimitive.isString)
        assertEquals(false, first["disabled"]!!.jsonPrimitive.booleanOrNull)
        assertEquals("Xcode and Swift builds", first["title"]!!.jsonPrimitive.content)
        assertEquals(0, first[TemplateHelper.IS_ON_COLUMN_KEY]!!.jsonPrimitive.intOrNull)

        val locked = TemplateHelper.substituteElement(toggleTemplate, packRows[2]).properties!!
        assertEquals(false, locked["isOn"]!!.jsonPrimitive.booleanOrNull)
        assertEquals(true, locked["disabled"]!!.jsonPrimitive.booleanOrNull)
    }

    @Test
    fun `other text and a missing column are off`() {
        val odd = TemplateHelper.substituteElement(toggleTemplate, listOf("maybe", "Title", "id")).properties!!
        assertEquals(false, odd["isOn"]!!.jsonPrimitive.booleanOrNull)
        assertEquals(false, odd["disabled"]!!.jsonPrimitive.booleanOrNull) // "$4" stays literal: not a Boolean
    }

    @Test
    fun `hidden and disabled come from the row on any element, text stays text`() {
        val text = ActionUIElement(
            type = "Text",
            properties = buildJsonObject { put("text", "$1"); put("hidden", "$2"); put("disabled", "$3") },
        )
        val out = TemplateHelper.substituteElement(text, listOf("Alpha", "1", "TRUE")).properties!!
        assertEquals(true, out["hidden"]!!.jsonPrimitive.booleanOrNull)
        assertEquals(true, out["disabled"]!!.jsonPrimitive.booleanOrNull)
        assertTrue(out["text"]!!.jsonPrimitive.isString)
        assertNull(out[TemplateHelper.IS_ON_COLUMN_KEY])
    }

    @Test
    fun `a literal Boolean is kept and names no column`() {
        val literal = ActionUIElement(
            type = "Toggle",
            properties = buildJsonObject { put("isOn", true); put("title", "$1") },
        )
        val out = TemplateHelper.substituteElement(literal, listOf("Alpha")).properties!!
        assertEquals(true, out["isOn"]!!.jsonPrimitive.booleanOrNull)
        assertNull(out[TemplateHelper.IS_ON_COLUMN_KEY])
    }

    // ---- A user toggle ----

    @Test
    fun `a user toggle writes the row, then fires with the row index and the new Boolean`() {
        val container = container()
        val fired = mutableListOf<List<Any?>>()
        var cellSeenByHandler = ""
        ActionUIModel.registerActionHandler("packs.toggled") { _, _, viewID, viewPartID, context ->
            fired += listOf(viewID, viewPartID, context)
            cellSeenByHandler = rowsOf(container)[viewPartID][0]
        }

        val taken = TemplateHelper.commitRowToggle(true, container, context(1), column = 0, actionID = "packs.toggled")

        assertTrue(taken)
        assertEquals(listOf("true", "Node", "node", "false"), rowsOf(container)[1])
        assertEquals(packRows[0], rowsOf(container)[0])
        assertEquals(listOf(listOf<Any?>(600, 1, true)), fired)
        assertEquals("the action fires after the write", "true", cellSeenByHandler)
    }

    @Test
    fun `the state survives a re-render`() {
        val container = container()
        TemplateHelper.commitRowToggle(true, container, context(1), column = 0, actionID = null)
        val redrawn = TemplateHelper.substituteElement(toggleTemplate, rowsOf(container)[1]).properties!!
        assertEquals(true, redrawn["isOn"]!!.jsonPrimitive.booleanOrNull)
    }

    @Test
    fun `without a column the Toggle is display-only`() {
        val container = container()
        var firedCount = 0
        ActionUIModel.registerActionHandler("packs.toggled") { _, _, _, _, _ -> firedCount++ }
        assertFalse(TemplateHelper.commitRowToggle(true, container, context(1), column = null, actionID = "packs.toggled"))
        assertEquals(packRows, rowsOf(container))
        assertEquals(0, firedCount)
    }

    @Test
    fun `a row shorter than the column is padded`() {
        val container = container(listOf(listOf("Alpha")))
        val short = TemplateContext(parentID = 600, rowIndex = 0, row = listOf("Alpha"))
        TemplateHelper.commitRowToggle(true, container, short, column = 2, actionID = null)
        assertEquals(listOf(listOf("Alpha", "", "true")), rowsOf(container))
    }

    @Test
    fun `a row the host moved is followed, a row that is gone is dropped`() {
        val moved = container(listOf(listOf("false", "New", "new", "false")) + packRows)
        val parts = mutableListOf<Int>()
        ActionUIModel.registerActionHandler("packs.toggled") { _, _, _, viewPartID, _ -> parts += viewPartID }
        assertTrue(TemplateHelper.commitRowToggle(true, moved, context(1), column = 0, actionID = "packs.toggled"))
        assertEquals(listOf("true", "Node", "node", "false"), rowsOf(moved)[2])
        assertEquals(packRows[0], rowsOf(moved)[1])
        assertEquals(listOf(2), parts)

        val gone = container(listOf(packRows[0]))
        assertFalse(TemplateHelper.commitRowToggle(true, gone, context(1), column = 0, actionID = "packs.toggled"))
        assertEquals(listOf(packRows[0]), rowsOf(gone))
        assertEquals(listOf(2), parts)
    }

    @Test
    fun `a selection on the toggled row follows it, one on another row stays`() {
        val container = container()
        container.value = packRows[1]
        TemplateHelper.commitRowToggle(true, container, context(1), column = 0, actionID = null)
        assertEquals(listOf("true", "Node", "node", "false"), container.value)

        val other = container()
        other.value = packRows[0]
        TemplateHelper.commitRowToggle(true, other, context(1), column = 0, actionID = null)
        assertEquals(packRows[0], other.value)
    }
}
