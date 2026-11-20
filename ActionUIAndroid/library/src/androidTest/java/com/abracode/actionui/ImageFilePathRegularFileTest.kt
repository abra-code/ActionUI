package com.abracode.actionui

import android.system.Os
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * An Image or Canvas `filePath` a document names could be a named pipe or a device. The
 * platform decoder opens the path on the main thread, and opening a pipe nobody writes to
 * never returns, so the window froze. Only a regular file is opened now; anything else
 * draws nothing and the rest of the document renders.
 */
@RunWith(AndroidJUnit4::class)
class ImageFilePathRegularFileTest {
    @get:Rule
    val rule = createComposeRule()

    private val window = "image-regular-file-${System.nanoTime()}"
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

    private fun pipe(): String {
        val path = File(folder, "pipe.png").path
        Os.mkfifo(path, 0x180) // 0600
        return path
    }

    @Test(timeout = 30_000)
    fun anImageFromANamedPipeDrawsNothingAndTheWindowRenders() {
        val path = pipe()
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "Image", "id": 2, "properties": { "filePath": "$path" } },
                    { "type": "Text", "id": 3, "properties": { "text": "After the image" } } ] }""",
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("After the image").assertExists()
    }

    @Test(timeout = 30_000)
    fun aCanvasImageFromANamedPipeOrADeviceDrawsNothingAndTheWindowRenders() {
        val path = pipe()
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "Canvas", "id": 2, "properties": { "frame": { "width": 100, "height": 100 }, "operations": [
                        { "type": "image", "frame": [0, 0, 0.5, 0.5], "filePath": "$path" },
                        { "type": "image", "frame": [0.5, 0.5, 0.5, 0.5], "filePath": "/dev/zero" } ] } },
                    { "type": "Text", "id": 3, "properties": { "text": "After the canvas" } } ] }""",
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("After the canvas").assertExists()
    }
}
