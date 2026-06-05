package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [Menu] - registry resolution, the valueless contract, and the
 * pure [menuItemKind] child classification. The `@Composable` DropdownMenu /
 * item rendering is exercised by the app.
 */
class MenuTest {

    @Test
    fun `Menu resolves in the registry and carries no value`() {
        assertSame(Menu, ActionUIRegistry.lookup("Menu"))
        assertEquals(ActionUIValueType.NONE, Menu.valueType)
    }

    @Test
    fun `menuItemKind classifies children`() {
        assertEquals(MenuItemKind.Action, menuItemKind(ActionUIElement(type = "Button")))
        assertEquals(MenuItemKind.Divider, menuItemKind(ActionUIElement(type = "Divider")))
        assertEquals(MenuItemKind.Section, menuItemKind(ActionUIElement(type = "Section")))
        assertEquals(MenuItemKind.Other, menuItemKind(ActionUIElement(type = "Text")))
        assertEquals(MenuItemKind.Other, menuItemKind(ActionUIElement(type = "Toggle")))
    }
}
