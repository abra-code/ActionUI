package com.abracode.actionui

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
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
 * A LoadableView whose document loads itself, directly or through another document,
 * is refused at the repeat with "Failed to load view: it includes itself". Before the
 * nesting rule, a file source loaded during composition without end, until the stack
 * or memory ran out. Siblings that show the same document both load it, and a device
 * file is refused rather than read.
 */
@RunWith(AndroidJUnit4::class)
class LoadableViewNestingTest {
    @get:Rule
    val rule = createComposeRule()

    private val window = "loadable-nesting-${System.nanoTime()}"
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
    fun aDocumentThatLoadsItselfIsRefusedAtTheRepeat() {
        val self = File(folder, "self.json")
        file("self.json", """{ "type": "VStack", "id": 20, "children": [
            { "type": "Text", "id": 22, "properties": { "text": "Loaded once" } },
            { "type": "LoadableView", "id": 21, "properties": { "filePath": "${self.path}" } } ] }""")
        rule.setContent {
            ActionUI.Render("""{ "type": "LoadableView", "id": 1, "properties": { "filePath": "${self.path}" } }""", windowUUID = window)
        }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: it includes itself").assertExists()
        assertEquals(1, rule.onAllNodesWithText("Loaded once").fetchSemanticsNodes().size)
    }

    @Test
    fun documentsThatLoadEachOtherAreRefusedAndSiblingsLoad() {
        val a = File(folder, "a.json")
        val b = File(folder, "b.json")
        file("a.json", """{ "type": "LoadableView", "id": 30, "properties": { "filePath": "${b.path}" } }""")
        file("b.json", """{ "type": "LoadableView", "id": 31, "properties": { "filePath": "${a.path}" } }""")
        val shared = file("shared.json", """{ "type": "Text", "id": 40, "properties": { "text": "Shared" } }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "LoadableView", "id": 2, "properties": { "filePath": "${a.path}" } },
                    { "type": "LoadableView", "id": 3, "properties": { "filePath": "${shared.path}" } },
                    { "type": "LoadableView", "id": 4, "properties": { "filePath": "${shared.path}" } } ] }""",
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: it includes itself").assertExists()
        assertEquals(2, rule.onAllNodesWithText("Shared").fetchSemanticsNodes().size)
    }

    @Test
    fun aSourceSwitchedBetweenRefusedAndAllowedAtRuntimeRendersEach() {
        val a = File(folder, "a.json")
        file("a.json", """{ "type": "VStack", "id": 30, "children": [
            { "type": "Text", "id": 32, "properties": { "text": "In A" } },
            { "type": "LoadableView", "id": 31, "properties": { "filePath": "${a.path}" } } ] }""")
        val shared = file("shared.json", """{ "type": "Text", "id": 40, "properties": { "text": "Shared" } }""")
        rule.setContent {
            ActionUI.Render("""{ "type": "LoadableView", "id": 1, "properties": { "filePath": "${a.path}" } }""", windowUUID = window)
        }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: it includes itself").assertExists()
        for (round in 0 until 2) {
            rule.runOnIdle { ActionUIModel.setElementValue(window, viewID = 31, value = shared.path) }
            rule.waitForIdle()
            rule.onNodeWithText("Shared").assertExists()
            rule.onNodeWithText("Failed to load view: it includes itself").assertDoesNotExist()
            rule.runOnIdle { ActionUIModel.setElementValue(window, viewID = 31, value = a.path) }
            rule.waitForIdle()
            rule.onNodeWithText("Failed to load view: it includes itself").assertExists()
            rule.onNodeWithText("Shared").assertDoesNotExist()
        }
        assertEquals(1, rule.onAllNodesWithText("In A").fetchSemanticsNodes().size)
    }

    @Test
    fun aDeviceFileIsRefused() {
        rule.setContent {
            ActionUI.Render("""{ "type": "LoadableView", "id": 1, "properties": { "filePath": "/dev/zero" } }""", windowUUID = window)
        }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: /dev/zero is not a regular file").assertExists()
    }
}
