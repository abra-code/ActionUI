package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for whole-container tap dispatch: the pure rule deciding WHICH view id
 * and row index a tapped `VStack`/`HStack`/`ZStack` dispatches with.
 *
 * The identity rule is the whole feature. A container tap that fires with the wrong id
 * is worse than one that does not fire at all: the handler runs, addresses some other
 * row, and looks like a working feature. That is exactly how the web behaved before this
 * change - it dispatched with the cloned instance's id, which `TemplateHelper` forces to
 * 0 - so the rule is pinned here rather than left to a Compose-level check.
 *
 * The `@Composable` half - `Modifier.containerAction` appending the clickable, and a
 * nested `Button` consuming the tap so the cell action does not also fire - is exercised
 * by the demo app (`VStack.containerAction.json`), as the rest of the Compose layer is.
 */
class ContainerActionHelperTest {

    private fun container(id: Int, actionID: String?) = ActionUIElement(
        id = id,
        type = "VStack",
        properties = buildJsonObject { if (actionID != null) put("actionID", actionID) },
    )

    private fun element(type: String, id: Int, actionID: String?) = ActionUIElement(
        id = id,
        type = type,
        properties = buildJsonObject { if (actionID != null) put("actionID", actionID) },
    )

    @Test
    fun `all three stack types are tappable and other types are not`() {
        // ZStack in particular had no coverage of any kind before this: the wiring is a
        // Compose modifier, so the type list is the only part of it a JVM test can reach.
        for (type in listOf("VStack", "HStack", "ZStack")) {
            assertEquals(
                ContainerActionDispatch("cell.open", viewID = 5, viewPartID = 0),
                containerActionDispatch(element(type, id = 5, actionID = "cell.open"), templateContext = null),
            )
        }
        for (type in listOf("Text", "Image", "List", "Button", "LazyVGrid")) {
            assertNull(
                "$type must not become a container tap target",
                containerActionDispatch(element(type, id = 5, actionID = "cell.open"), templateContext = null),
            )
        }
    }

    @Test
    fun `no actionID means no dispatch and no tap target`() {
        assertNull(containerActionDispatch(container(id = 5, actionID = null), templateContext = null))
    }

    @Test
    fun `a blank actionID is refused rather than wiring a dead tap target`() {
        assertNull(containerActionDispatch(container(id = 5, actionID = ""), templateContext = null))
        assertNull(containerActionDispatch(container(id = 5, actionID = "   "), templateContext = null))
    }

    @Test
    fun `outside a template a container dispatches as itself`() {
        val dispatch = containerActionDispatch(container(id = 5, actionID = "cell.open"), templateContext = null)
        assertEquals(ContainerActionDispatch("cell.open", viewID = 5, viewPartID = 0), dispatch)
    }

    @Test
    fun `inside a template row it dispatches the owning container id and the row index`() {
        // The cloned instance's own id is 0 and identifies nothing - the context is the
        // only place row identity exists. This is the case the gap was about.
        val dispatch = containerActionDispatch(
            container(id = 0, actionID = "row.open"),
            templateContext = TemplateContext(parentID = 100, rowIndex = 4),
        )
        assertEquals(ContainerActionDispatch("row.open", viewID = 100, viewPartID = 4), dispatch)
    }

    @Test
    fun `row zero is a real row, not an absent context`() {
        // Pins that the presence of a context, not the value of the row index, decides
        // whose id is dispatched - so the FIRST row is not silently treated as "no
        // template". Cheap here; load-bearing on the web, where 0 is falsy and the
        // natural shorthand really does collapse the two (see modifier-resolver.test.mjs).
        val dispatch = containerActionDispatch(
            container(id = 0, actionID = "row.open"),
            templateContext = TemplateContext(parentID = 100, rowIndex = 0),
        )
        assertEquals(ContainerActionDispatch("row.open", viewID = 100, viewPartID = 0), dispatch)
    }

    @Test
    fun `the template context wins over a container that kept a real id`() {
        // A template instance normally has id 0, but nothing guarantees it: an author can
        // put an id on the template's root element. Row identity still comes from the
        // context, matching Views/Button.kt, so a cell and a button inside it agree.
        val dispatch = containerActionDispatch(
            container(id = 77, actionID = "row.open"),
            templateContext = TemplateContext(parentID = 100, rowIndex = 2),
        )
        assertEquals(ContainerActionDispatch("row.open", viewID = 100, viewPartID = 2), dispatch)
    }
}
