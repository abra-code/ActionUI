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
 * A VideoPlayer `file://` url a document names could be a named pipe. MediaPlayer opens a
 * file: address in the app's own process, on the main thread, once the video surface is
 * made, and opening a pipe nobody writes to never returns, so the window froze. Only a
 * regular file is opened now; anything else is logged and the rest of the document renders.
 */
@RunWith(AndroidJUnit4::class)
class VideoPlayerRegularFileTest {
    @get:Rule
    val rule = createComposeRule()

    private val window = "video-regular-file-${System.nanoTime()}"
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

    @Test(timeout = 30_000)
    fun aVideoFromANamedPipeIsNotOpenedAndTheWindowRenders() {
        val path = File(folder, "pipe.mp4").path
        Os.mkfifo(path, 0x180) // 0600
        rule.setContent {
            ActionUI.Render(
                """{ "type": "VStack", "id": 1, "children": [
                    { "type": "VideoPlayer", "id": 2, "properties": { "url": "file://$path", "frame": { "height": 100 } } },
                    { "type": "Text", "id": 3, "properties": { "text": "After the video" } } ] }""",
                windowUUID = window,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("After the video").assertExists()
    }
}
