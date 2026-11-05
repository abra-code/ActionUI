package com.abracode.actionui.addon.hostsurface

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.test.junit4.createComposeRule
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIModel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The element in a real ActionUI document on a device: a SurfaceView's surface is announced with its size;
 * hidden and padding changes keep it (no DESTROYED); a replaced client is told DESTROYED before the new one gets
 * CREATED; removing the element destroys the surface.
 */
@RunWith(AndroidJUnit4::class)
class HostSurfaceDocumentTest {
    @get:Rule
    val rule = createComposeRule()

    private class Recorder(val name: String, val log: MutableList<String>) : HostSurfaceDelegate {
        val events = mutableListOf<HostSurfaceEvent>()
        val infos = mutableListOf<HostSurfaceInfo>()
        override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
            events += event
            infos += info
            log += "$name $event"
        }
    }

    private val window = "hostsurface-${System.nanoTime()}"
    private val log = mutableListOf<String>()
    private val client = Recorder("first", log)

    private val document = """
        { "type": "VStack", "id": 1, "children": [
            { "type": "Text", "id": 2, "properties": { "text": "above" } },
            { "type": "HostSurface", "id": 5, "properties": {
                "surfaceName": "test.canvas", "frame": { "width": 200, "height": 120 } } }
        ] }
    """.trimIndent()

    @Before
    fun setUp() {
        HostSurfaceElement.register()
        rule.runOnIdle { assertTrue(HostSurfaces.setDelegate("test.canvas", client)) }
        rule.setContent { ActionUI.Render(document, windowUUID = window) }
        rule.waitUntil(5_000) { client.events.isNotEmpty() }
    }

    @After
    fun tearDown() {
        rule.runOnIdle { HostSurfaces.setDelegate("test.canvas", null) }
    }

    private fun write(property: String, value: Any) {
        rule.runOnIdle { ActionUIModel.setElementProperty(window, 5, property, value) }
        rule.waitForIdle()
        // The SurfaceHolder callbacks come on a later frame.
        Thread.sleep(300)
        rule.waitForIdle()
    }

    @Test
    fun theSurfaceIsAnnouncedWithItsSize() {
        assertEquals(HostSurfaceEvent.CREATED, client.events.first())
        val info = client.infos.first()
        assertTrue("a pixel size (${info.widthPixels}x${info.heightPixels})", info.widthPixels > 0 && info.heightPixels > 0)
        assertEquals(200f, info.widthPoints, 1f)
        assertEquals(120f, info.heightPoints, 1f)
        assertFalse(info.composited)
        assertEquals(window, info.windowUUID)
        assertEquals(5, info.viewID)
    }

    @Test
    fun hiddenAndPaddingKeepTheSurface() {
        write("hidden", true)
        write("hidden", false)
        write("padding", 20)
        write("padding", 0)
        assertFalse("no DESTROYED: ${client.events}", client.events.contains(HostSurfaceEvent.DESTROYED))
        assertEquals("one CREATED: ${client.events}", 1, client.events.count { it == HostSurfaceEvent.CREATED })
        assertTrue("hidden suspended it: ${client.events}", client.events.contains(HostSurfaceEvent.SUSPENDED))
        assertEquals("one surface throughout", 1, client.infos.map { it.surfaceID }.toSet().size)
    }

    @Test
    fun aReplacedClientIsToldFirst() {
        val second = Recorder("second", log)
        rule.runOnIdle { HostSurfaces.setDelegate("test.canvas", second) }
        assertEquals(listOf("first CREATED", "first DESTROYED", "second CREATED"), log)
        assertTrue(client.infos.first().surfaceID != second.infos.first().surfaceID)
    }

    @Test
    fun removingTheElementDestroysTheSurface() {
        rule.runOnIdle { ActionUIModel.removeElement(window, viewID = 5) }
        rule.waitUntil(5_000) { client.events.contains(HostSurfaceEvent.DESTROYED) }
        assertEquals(HostSurfaceEvent.DESTROYED, client.events.last())
    }
}
