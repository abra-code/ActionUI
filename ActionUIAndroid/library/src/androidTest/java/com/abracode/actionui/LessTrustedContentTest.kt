package com.abracode.actionui

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.LoggerLevel
import java.io.File
import java.util.Collections
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A document a LoadableView loads from a file outside the app's resources is less trusted,
 * and so is everything in it: its Link opens no file address, its WebView shows no local
 * file, and it may not use the id of a trusted element. The host's own document is not held
 * to those rules.
 */
@RunWith(AndroidJUnit4::class)
class LessTrustedContentTest {
    @get:Rule
    val rule = createComposeRule()

    private val window = "less-trusted-${System.nanoTime()}"
    private lateinit var folder: File

    private class Recording : ActionUILogger {
        val warnings: MutableList<String> = Collections.synchronizedList(mutableListOf())
        override fun log(message: String, level: LoggerLevel) {
            if (level <= LoggerLevel.warning) warnings += message
        }
    }

    private val logger = Recording()

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
    fun jsonFromAFileHasItsLinkAndWebViewHeldToTheLessTrustedRules() {
        val document = file("remote-like.json", """{ "type": "VStack", "id": 20, "children": [
            { "type": "Link", "id": 21, "properties": { "title": "Open the file", "url": "file:///sdcard/Download/a.pdf" } },
            { "type": "WebView", "id": 22, "properties": { "url": "file:///sdcard/Download/a.html" } } ] }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "LoadableView", "id": 2, "properties": { "filePath": "${document.path}" } } ] }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        val origin = ActionUIModel.origin(window, 21)
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, origin?.trust)
        assertEquals(2, origin?.parentID)
        assertEquals(JSONContentOrigin.HOST, ActionUIModel.origin(window, 1))

        rule.onNodeWithText("Open the file").performClick()
        rule.waitForIdle()
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "Link not opening file:///sdcard/Download/a.pdf: the trust policy refuses it" })
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "WebView not showing file:///sdcard/Download/a.html: the trust policy refuses it" })
    }

    @Test
    fun jsonFromAFileMayNotUseATrustedElementsId() {
        val document = file("taken-id.json", """{ "type": "Text", "id": 1, "properties": { "text": "Pretends to be the root" } }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "LoadableView", "id": 2, "properties": { "filePath": "${document.path}" } } ] }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: id conflict: 1 already in the window").assertExists()
        assertEquals(0, rule.onAllNodesWithText("Pretends to be the root").fetchSemanticsNodes().size)
    }

    @Test
    fun theHostsOwnLinkIsNotAsked() {
        rule.setContent {
            ActionUI.Render(
                """{ "type": "Link", "id": 1, "properties": { "title": "Host link", "url": "file:///sdcard/Download/a.pdf" } }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.onNodeWithText("Host link").performClick()
        rule.waitForIdle()
        assertTrue(logger.warnings.toString(), logger.warnings.none { it.startsWith("Link not opening") })
    }
}
