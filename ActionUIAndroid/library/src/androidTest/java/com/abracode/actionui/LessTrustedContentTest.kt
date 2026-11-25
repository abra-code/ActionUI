package com.abracode.actionui

import androidx.compose.foundation.clickable
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.LoggerLevel
import java.io.File
import kotlinx.serialization.json.JsonPrimitive
import java.util.Collections
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * ActionUI JSON that a LoadableView loads from a file outside the app's resources is less trusted,
 * and so is everything in it: its Link opens no file address, its WebView shows no local
 * file, and it may not use the id of a trusted element. The host's own JSON is not held
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
        val jsonFile = file("remote-like.json", """{ "type": "VStack", "id": 20, "children": [
            { "type": "Link", "id": 21, "properties": { "title": "Open the file", "url": "file:///sdcard/Download/a.pdf" } },
            { "type": "WebView", "id": 22, "properties": { "url": "file:///sdcard/Download/a.html" } } ] }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "LoadableView", "id": 2, "properties": { "filePath": "${jsonFile.path}" } } ] }""",
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
        val jsonFile = file("taken-id.json", """{ "type": "Text", "id": 1, "properties": { "text": "Pretends to be the root" } }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "LoadableView", "id": 2, "properties": { "filePath": "${jsonFile.path}" } } ] }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("Failed to load view: id conflict: 1 already in the window").assertExists()
        assertEquals(0, rule.onAllNodesWithText("Pretends to be the root").fetchSemanticsNodes().size)
    }

    @Test
    fun jsonFromAFileReadsNoLocalFileOutsideTheResources() {
        val picture = File(folder, "pic.png").apply {
            val bitmap = android.graphics.Bitmap.createBitmap(2, 2, android.graphics.Bitmap.Config.ARGB_8888)
            outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        }
        val jsonFile = file("pictures.json", """{ "type": "VStack", "id": 20, "children": [
            { "type": "Image", "id": 21, "properties": { "filePath": "${picture.path}" } },
            { "type": "AsyncImage", "id": 22, "properties": { "url": "file://${picture.path}" } },
            { "type": "VideoPlayer", "id": 23, "properties": { "url": "content://media/external/video/media/1" } } ] }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "Image", "id": 2, "properties": { "filePath": "${picture.path}" } },
                    { "type": "LoadableView", "id": 3, "properties": { "filePath": "${jsonFile.path}" } } ] }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.waitUntil(5_000) { logger.warnings.count { it == "Not reading ${picture.path}: the trust policy refuses it" } >= 2 }
        // Once for the Image, once for the AsyncImage; the host's own Image of the same file is not asked.
        assertEquals(logger.warnings.toString(), 2, logger.warnings.count { it == "Not reading ${picture.path}: the trust policy refuses it" })
        assertTrue(logger.warnings.toString(), logger.warnings.any {
            it == "VideoPlayer not playing 'content://media/external/video/media/1': the trust policy refuses it"
        })
    }

    @Test
    fun jsonFromAFileTitlesNoScreenAndPresentsNoPopover() {
        val jsonFile = file("chrome.json", """{ "type": "NavigationStack", "id": 20,
            "content": { "type": "VStack", "id": 21, "properties": { "navigationTitle": "Bank sign-in" }, "children": [
                { "type": "Text", "id": 22, "properties": { "text": "Tap for more" },
                  "popover": { "type": "Text", "id": 23, "properties": { "text": "Enter your password" } } } ] } }""")
        rule.setContent {
            ActionUI.Render(
                """{ "type": "LoadableView", "id": 1, "properties": { "filePath": "${jsonFile.path}" } }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("Tap for more").assertExists()
        assertEquals(0, rule.onAllNodesWithText("Bank sign-in").fetchSemanticsNodes().size)
        rule.onNodeWithText("Tap for more").performClick()
        rule.waitForIdle()
        assertEquals(0, rule.onAllNodesWithText("Enter your password").fetchSemanticsNodes().size)
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "Not setting the title for element 21: the trust policy refuses it" })
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "Not presenting a popover for element 22: the trust policy refuses it" })
    }

    @Test
    fun theHostsOwnTitleAndPopoverAreShown() {
        rule.setContent {
            ActionUI.Render(
                """{ "type": "NavigationStack", "id": 20,
                    "content": { "type": "VStack", "id": 21, "properties": { "navigationTitle": "Host title" }, "children": [
                        { "type": "Text", "id": 22, "properties": { "text": "Tap for more" },
                          "popover": { "type": "Text", "id": 23, "properties": { "text": "Host popover" } } } ] } }""",
                logger = logger,
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("Host title").assertExists()
        rule.onNodeWithText("Tap for more").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Host popover").assertExists()
    }

    @Test
    fun anImageOverSixtyFourMegapixelsIsNotDecoded() {
        // A PNG whose header declares 9000 x 9000 pixels (81 million), with only its first row of data.
        fun chunk(kind: String, data: ByteArray): ByteArray {
            val body = kind.toByteArray(Charsets.US_ASCII) + data
            val crc = java.util.zip.CRC32().apply { update(body) }.value.toInt()
            return java.nio.ByteBuffer.allocate(4).putInt(data.size).array() + body + java.nio.ByteBuffer.allocate(4).putInt(crc).array()
        }
        val header = java.nio.ByteBuffer.allocate(13).putInt(9000).putInt(9000).put(byteArrayOf(8, 6, 0, 0, 0)).array()
        val huge = File(folder, "huge.png").apply {
            // A first data chunk too (one row's worth): decoders read the size only once the data begins.
            val row = java.io.ByteArrayOutputStream().also { out ->
                java.util.zip.DeflaterOutputStream(out).use { it.write(ByteArray(1 + 9000 * 4)) }
            }.toByteArray()
            writeBytes(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a) + chunk("IHDR", header) + chunk("IDAT", row) + chunk("IEND", ByteArray(0)))
        }
        rule.setContent {
            ActionUI.Render("""{ "type": "Image", "id": 1, "properties": { "filePath": "${huge.path}" } }""", logger = logger, windowUUID = window)
        }
        rule.waitForIdle()
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "Image not shown: ${huge.path} is 9000 x 9000 pixels, more than 67108864" })
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

    private val sheetJSON = """{ "type": "Button", "id": 30, "properties": { "title": "Open the sheet" },
        "sheet": { "type": "Text", "id": 31, "properties": { "text": "Sheet content" } } }"""

    @Test
    fun aWindowJSONFromAFilePresentsNoSheet() {
        val jsonFile = file("sheet.json", sheetJSON)
        rule.setContent { ActionUI.RenderSource(jsonFile.path, logger = logger, windowUUID = window) }
        rule.waitForIdle()
        rule.onNodeWithText("Open the sheet").performClick()
        rule.waitForIdle()
        assertEquals(0, rule.onAllNodesWithText("Sheet content").fetchSemanticsNodes().size)
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "Not presenting a sheet or cover for element 30: the trust policy refuses it" })
    }

    @Test
    fun theHostsOwnSheetIsPresented() {
        rule.setContent { ActionUI.Render(sheetJSON, logger = logger, windowUUID = window) }
        rule.waitForIdle()
        rule.onNodeWithText("Open the sheet").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Sheet content").assertExists()
    }

    /** Opens its `url` through LocalUriHandler on a tap, as Markdown text links do. */
    private object UriProbe : ActionUIViewConstruction {
        @Composable
        override fun BuildView(element: ActionUIElement, modifier: Modifier) {
            val handler = LocalUriHandler.current
            val url = (element.properties?.get("url") as? JsonPrimitive)?.content ?: return
            Text("Probe $url", modifier.clickable { handler.openUri(url) })
        }
    }

    @Test
    fun jsonFromAFileHasAUriHandlerThatOpensOnlyWhatThePolicyAllows() {
        ActionUIRegistry.register("UriProbe", UriProbe)
        val opened = Collections.synchronizedList(mutableListOf<String>())
        val recorder = object : UriHandler {
            override fun openUri(uri: String) { opened += uri }
        }
        val jsonFile = file("links.json", """{ "type": "VStack", "id": 20, "children": [
            { "type": "UriProbe", "properties": { "url": "tel:123" } },
            { "type": "UriProbe", "properties": { "url": "https://example.com/" } } ] }""")
        rule.setContent {
            CompositionLocalProvider(LocalUriHandler provides recorder) {
                ActionUI.Render(
                    """{ "type": "VStack", "id": 1, "children": [
                        { "type": "UriProbe", "properties": { "url": "tel:456" } },
                        { "type": "LoadableView", "id": 2, "properties": { "filePath": "${jsonFile.path}" } } ] }""",
                    logger = logger,
                    windowUUID = window,
                )
            }
        }
        rule.waitForIdle()
        rule.onNodeWithText("Probe tel:123").performClick()
        rule.onNodeWithText("Probe https://example.com/").performClick()
        rule.onNodeWithText("Probe tel:456").performClick()
        rule.waitForIdle()
        assertEquals(listOf("https://example.com/", "tel:456"), opened.toList())
        assertTrue(logger.warnings.toString(), logger.warnings.any { it == "Not opening tel:123: the trust policy refuses it" })
    }
}
