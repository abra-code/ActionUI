package com.abracode.actionui.Common

import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [ActionUIRegistry]'s type → builder mapping. The builders'
 * `BuildView` is `@Composable` and exercised via instrumentation; here we only
 * assert that every shipped element type resolves (and unknown/empty types do
 * not), which needs no Compose runtime.
 */
class ActionUIRegistryTest {

    @Test
    fun `built-in element types resolve to their builders`() {
        assertSame(com.abracode.actionui.Views.Text, ActionUIRegistry.lookup("Text"))
        assertSame(com.abracode.actionui.Views.VStack, ActionUIRegistry.lookup("VStack"))
        assertSame(com.abracode.actionui.Views.HStack, ActionUIRegistry.lookup("HStack"))
        assertSame(com.abracode.actionui.Views.Button, ActionUIRegistry.lookup("Button"))
        assertSame(com.abracode.actionui.Views.Divider, ActionUIRegistry.lookup("Divider"))
        assertSame(com.abracode.actionui.Views.Spacer, ActionUIRegistry.lookup("Spacer"))
    }

    @Test
    fun `unknown type returns null`() {
        assertNull(ActionUIRegistry.lookup("NotARealElement"))
    }

    @Test
    fun `empty type returns null`() {
        assertNull(ActionUIRegistry.lookup(""))
    }

    @Test
    fun `lookup is case-sensitive`() {
        assertNull(ActionUIRegistry.lookup("divider"))
        assertNull(ActionUIRegistry.lookup("BUTTON"))
    }

    @Test
    fun `register adds a custom type retrievable via lookup`() {
        val custom = com.abracode.actionui.Views.Text // any builder instance works as a stand-in
        ActionUIRegistry.register("CustomXYZ", custom)
        assertSame(custom, ActionUIRegistry.lookup("CustomXYZ"))
    }
}
