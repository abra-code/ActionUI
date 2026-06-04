package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [Section] and [Form] / [Table] registry presence. Section seeds
 * empty rows for its data-driven (template) mode; the header / children / template
 * `@Composable` rendering is exercised by the app.
 */
class SectionTest {

    @Test
    fun `Section, Form and Table resolve and carry no value`() {
        assertSame(Section, ActionUIRegistry.lookup("Section"))
        assertSame(Form, ActionUIRegistry.lookup("Form"))
        assertSame(Table, ActionUIRegistry.lookup("Table"))
        assertEquals(ActionUIValueType.NONE, Section.valueType)
        assertEquals(ActionUIValueType.NONE, Form.valueType)
        assertEquals(ActionUIValueType.NONE, Table.valueType)
    }

    @Test
    fun `Section seeds empty rows for template mode`() {
        assertEquals(
            mapOf("content" to emptyList<List<String>>()),
            Section.initialStates(ActionUIElement(id = 1, type = "Section")),
        )
    }
}
