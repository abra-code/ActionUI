package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Cross-cutting test for the data-driven (`template`) container set: every
 * container that renders a template per data row must seed
 * `states[`[ActionUIModel.ROWS_STATE_KEY]`]` empty via `initialStates`, so a
 * host can address the rows by id before any data arrives. The per-row
 * substitution itself is covered by `Helpers/TemplateHelperTest`; the
 * `@Composable` rendering is exercised by the app.
 */
class TemplateContainersTest {

    /** Every Android container supporting template mode, as on Apple. */
    private val templateContainers: Map<String, ActionUIViewConstruction> = mapOf(
        "VStack" to VStack,
        "HStack" to HStack,
        "ZStack" to ZStack,
        "LazyVStack" to LazyVStack,
        "LazyHStack" to LazyHStack,
        "LazyVGrid" to LazyVGrid,
        "LazyHGrid" to LazyHGrid,
        "Group" to Group,
        "GroupBox" to GroupBox,
        "List" to ListView,
        "Section" to Section,
    )

    @Test
    fun `every template container seeds empty rows`() {
        templateContainers.forEach { (type, builder) ->
            val states = builder.initialStates(ActionUIElement(id = 1, type = type))
            assertEquals(
                "$type must seed empty rows for template mode",
                emptyList<kotlin.collections.List<String>>(),
                states[ActionUIModel.ROWS_STATE_KEY],
            )
        }
    }

    @Test
    fun `DisclosureGroup seeds empty rows alongside isExpanded`() {
        val states = DisclosureGroup.initialStates(ActionUIElement(id = 1, type = "DisclosureGroup"))
        assertEquals(emptyList<kotlin.collections.List<String>>(), states[ActionUIModel.ROWS_STATE_KEY])
        assertEquals(false, states["isExpanded"])
    }
}
