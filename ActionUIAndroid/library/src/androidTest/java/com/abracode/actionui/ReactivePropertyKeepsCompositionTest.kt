package com.abracode.actionui

import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.viewinterop.AndroidView
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUIInputEnabled
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A runtime write of a reactive property (`hidden`, `disabled`, `tint`,
 * `foregroundStyle`) must not dispose the element's composition. Before the fix,
 * `ProvideReactiveEnvironment` called its content directly when no reactive value was
 * set and inside a `CompositionLocalProvider` otherwise, so every toggle moved the
 * subtree to a new composition group: remembered state was lost and an `AndroidView`
 * released its view and ran its factory again. This test counts both on a probe element
 * that, like a client-drawn surface, keeps one `AndroidView` with no branches.
 */
@RunWith(AndroidJUnit4::class)
class ReactivePropertyKeepsCompositionTest {
    @get:Rule
    val rule = createComposeRule()

    private class Counts {
        var factories = 0
        var releases = 0
        var remembers = 0
        var inputEnabled = true
        var enabled = true
    }

    private val counts = mutableMapOf<Int, Counts>()

    private inner class Probe : ActionUIViewConstruction {
        @Composable
        override fun BuildView(element: ActionUIElement, modifier: Modifier) {
            val c = counts.getOrPut(element.id) { Counts() }
            remember { c.remembers += 1; c.remembers }
            c.inputEnabled = LocalActionUIInputEnabled.current
            c.enabled = LocalActionUIEnabled.current
            AndroidView(
                modifier = modifier,
                factory = { context -> c.factories += 1; View(context) },
                onRelease = { c.releases += 1 },
            )
        }
    }

    // JUnit makes a new instance per test, so each test gets its own window and starts
    // without the property overrides another test wrote.
    private val window = "reactive-keeps-composition-${System.nanoTime()}"

    // 2: a probe that is written to directly. 4: a probe inside a stack that is written to.
    // 5: a searchable probe, whose hidden content takes a separate path (SearchableHelper.kt).
    private val document = """
        { "type": "VStack", "id": 1, "children": [
            { "type": "ReactiveProbe", "id": 2, "properties": { "frame": { "width": 100, "height": 40 } } },
            { "type": "VStack", "id": 3, "children": [
                { "type": "ReactiveProbe", "id": 4, "properties": { "frame": { "width": 100, "height": 40 } } }
            ] },
            { "type": "ReactiveProbe", "id": 5, "properties": {
                "frame": { "width": 100, "height": 40 },
                "searchable": { "actionID": "probe.search" } } }
        ] }
    """.trimIndent()

    @Before
    fun setUp() {
        ActionUIRegistry.register("ReactiveProbe", Probe())
        rule.setContent { ActionUI.Render(document, windowUUID = window) }
        rule.waitForIdle()
    }

    private fun write(viewID: Int, property: String, value: Any) {
        rule.runOnIdle { ActionUIModel.setElementProperty(window, viewID, property, value) }
        rule.waitForIdle()
    }

    private fun assertComposedOnce(viewID: Int, after: String) {
        val c = counts.getValue(viewID)
        assertEquals("view $viewID factory runs after $after", 1, c.factories)
        assertEquals("view $viewID releases after $after", 0, c.releases)
        assertEquals("view $viewID remember runs after $after", 1, c.remembers)
    }

    @Test
    fun hiddenToggleKeepsTheElementComposition() {
        for (id in listOf(2, 3, 5)) {
            val probe = if (id == 3) 4 else id
            assertComposedOnce(probe, "load")
            for (round in 1..2) {
                write(id, "hidden", true)
                assertEquals("view $probe input while hidden", false, counts.getValue(probe).inputEnabled)
                assertComposedOnce(probe, "hide $round of view $id")
                write(id, "hidden", false)
                assertEquals("view $probe input after unhide", true, counts.getValue(probe).inputEnabled)
                assertComposedOnce(probe, "unhide $round of view $id")
            }
        }
    }

    @Test
    fun otherReactivePropertiesKeepTheElementComposition() {
        write(2, "disabled", true)
        assertEquals("enabled while disabled", false, counts.getValue(2).enabled)
        assertComposedOnce(2, "disable")
        write(2, "disabled", false)
        assertComposedOnce(2, "enable")
        write(2, "tint", "red")
        assertComposedOnce(2, "tint")
        write(2, "foregroundStyle", "blue")
        assertComposedOnce(2, "foregroundStyle")
    }
}
