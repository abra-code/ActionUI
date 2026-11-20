package com.abracode.actionui

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.abracode.actionui.Common.ActionUIModel
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A LoadableView inside loaded content keeps its own content's view models when the
 * outer LoadableView reloads. The outer reload removes everything its content owned,
 * nested content included, and the inner LoadableView, still showing the same source,
 * merges its content again.
 */
@RunWith(AndroidJUnit4::class)
class LoadableViewReloadTest {
    @get:Rule
    val rule = createComposeRule()

    private val window = "loadable-reload-${System.nanoTime()}"
    private lateinit var folder: File

    @Before
    fun setUp() {
        val cache = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir
        folder = File(cache, window).apply { mkdirs() }
    }

    @After
    fun tearDown() {
        folder.deleteRecursively()
    }

    private fun file(name: String, json: String): File = File(folder, name).apply { writeText(json) }

    @Test
    fun anOuterReloadKeepsTheInnerContentModels() {
        val inner = file("inner.json", """{ "type": "TextField", "id": 40, "properties": { "text": "inner" } }""")
        fun outer(name: String, label: String) = file(name, """{ "type": "VStack", "id": 30, "children": [
            { "type": "Text", "id": 32, "properties": { "text": "$label" } },
            { "type": "LoadableView", "id": 31, "properties": { "filePath": "${inner.path}" } } ] }""")
        val first = outer("first.json", "First")
        val second = outer("second.json", "Second")
        rule.setContent {
            ActionUI.Render("""{ "type": "LoadableView", "id": 2, "properties": { "filePath": "${first.path}" } }""", windowUUID = window)
        }
        rule.waitForIdle()
        rule.onNodeWithText("First").assertExists()
        assertEquals("inner", ActionUIModel.getElementValue(window, viewID = 40))

        rule.runOnIdle { ActionUIModel.setElementValue(window, viewID = 2, value = second.path) }
        rule.waitForIdle()
        rule.onNodeWithText("Second").assertExists()
        assertEquals("inner", ActionUIModel.getElementValue(window, viewID = 40))
    }
}
