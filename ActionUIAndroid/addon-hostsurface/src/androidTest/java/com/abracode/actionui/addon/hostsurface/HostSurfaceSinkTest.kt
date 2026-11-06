package com.abracode.actionui.addon.hostsurface

import android.graphics.Bitmap
import android.os.Handler
import android.os.HandlerThread
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIModel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The frame sink on a device ("kind": "sink"): announced as a frame sink, frames presented from another thread
 * are shown (read back from the SurfaceView), each pixel layout gives the same colors, and a destroyed surface
 * takes no frames.
 */
@RunWith(AndroidJUnit4::class)
class HostSurfaceSinkTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private class Recorder : HostSurfaceDelegate {
        val events = mutableListOf<HostSurfaceEvent>()
        val infos = mutableListOf<HostSurfaceInfo>()
        override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
            events += event
            infos += info
        }
    }

    private val window = "hostsurface-sink-${System.nanoTime()}"
    private val client = Recorder()

    private val document = """
        { "type": "VStack", "id": 1, "children": [
            { "type": "HostSurface", "id": 5, "properties": {
                "surfaceName": "test.sink", "kind": "sink", "frame": { "width": 120, "height": 80 } } }
        ] }
    """.trimIndent()

    @Before
    fun setUp() {
        HostSurfaceElement.register()
        rule.runOnIdle { assertTrue(HostSurfaces.setDelegate("test.sink", client)) }
        rule.setContent { ActionUI.Render(document, windowUUID = window) }
        rule.waitUntil(5_000) { client.events.isNotEmpty() }
    }

    @After
    fun tearDown() {
        rule.runOnIdle { HostSurfaces.setDelegate("test.sink", null) }
    }

    /** One frame of one color, given as four bytes in the format's order, presented from another thread. */
    private fun presentFromAnotherThread(surfaceID: Long, bytes: ByteArray, format: HostPixelFormat,
                                         width: Int = 8, height: Int = 4): Boolean {
        val pixels = ByteArray(width * height * 4) { bytes[it % 4] }
        var shown = false
        thread { shown = HostSurfaces.presentPixels(surfaceID, pixels, width, height, format = format) }.join()
        return shown
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) {
            return view
        }
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    /** The center pixel of what the SurfaceView shows, as ARGB. */
    private fun shownColor(): Int {
        val surfaceView = rule.runOnIdle { findSurfaceView(rule.activity.window.decorView) }!!
        val bitmap = Bitmap.createBitmap(8, 4, Bitmap.Config.ARGB_8888)
        val done = CountDownLatch(1)
        var result = -1
        val handlerThread = HandlerThread("pixelcopy").apply { start() }
        PixelCopy.request(surfaceView, bitmap, { code -> result = code; done.countDown() }, Handler(handlerThread.looper))
        assertTrue("PixelCopy finished", done.await(5, TimeUnit.SECONDS))
        handlerThread.quitSafely()
        assertEquals("PixelCopy succeeded", PixelCopy.SUCCESS, result)
        return bitmap.getPixel(4, 2)
    }

    @Test
    fun aSinkIsAnnouncedAsAFrameSink() {
        assertEquals(HostSurfaceEvent.CREATED, client.events.first())
        assertTrue(client.infos.first().frameSink)
    }

    @Test
    fun framesFromAnotherThreadAreShownInEachLayout() {
        val surfaceID = client.infos.first().surfaceID
        // Red 0x30, green 0x60, blue 0x90, opaque, in each layout.
        val cases = listOf(
            HostPixelFormat.RGBA8_PREMULTIPLIED to byteArrayOf(0x30, 0x60, 0x90.toByte(), 0xFF.toByte()),
            HostPixelFormat.BGRA8_PREMULTIPLIED to byteArrayOf(0x90.toByte(), 0x60, 0x30, 0xFF.toByte()),
            HostPixelFormat.RGBX8 to byteArrayOf(0x30, 0x60, 0x90.toByte(), 0x00),
            HostPixelFormat.BGRX8 to byteArrayOf(0x90.toByte(), 0x60, 0x30, 0x00),
        )
        for ((format, bytes) in cases) {
            assertTrue("$format", presentFromAnotherThread(surfaceID, bytes, format))
            rule.waitForIdle()
            Thread.sleep(100)
            assertEquals("$format", 0xFF306090.toInt(), shownColor())
        }
    }

    @Test
    fun aReplacedClientsFrameIsCleared() {
        val surfaceID = client.infos.first().surfaceID
        assertTrue(presentFromAnotherThread(surfaceID, byteArrayOf(0x30, 0x60, 0x90.toByte(), 0xFF.toByte()),
                                            HostPixelFormat.RGBA8_PREMULTIPLIED))
        rule.waitForIdle()
        Thread.sleep(100)
        assertEquals(0xFF306090.toInt(), shownColor())
        val second = Recorder()
        rule.runOnIdle { HostSurfaces.setDelegate("test.sink", second) }
        rule.waitForIdle()
        Thread.sleep(100)
        assertEquals("the old client's frame is cleared", 0, shownColor())
        assertFalse("the old surface takes no frames",
                    presentFromAnotherThread(surfaceID, byteArrayOf(1, 2, 3, 4), HostPixelFormat.RGBA8_PREMULTIPLIED))
        assertTrue("the new one does", presentFromAnotherThread(second.infos.first().surfaceID,
                   byteArrayOf(0x30, 0x60, 0x90.toByte(), 0xFF.toByte()), HostPixelFormat.RGBA8_PREMULTIPLIED))
    }

    @Test
    fun aDestroyedSurfaceTakesNoFrames() {
        val surfaceID = client.infos.first().surfaceID
        assertFalse("a short buffer", HostSurfaces.presentPixels(surfaceID, ByteArray(8), 8, 4))
        assertFalse("no width", HostSurfaces.presentPixels(surfaceID, ByteArray(64), 0, 4))
        rule.runOnIdle { ActionUIModel.removeElement(window, viewID = 5) }
        rule.waitUntil(5_000) { client.events.contains(HostSurfaceEvent.DESTROYED) }
        assertFalse(presentFromAnotherThread(surfaceID, byteArrayOf(1, 2, 3, 4), HostPixelFormat.RGBA8_PREMULTIPLIED))
    }
}
