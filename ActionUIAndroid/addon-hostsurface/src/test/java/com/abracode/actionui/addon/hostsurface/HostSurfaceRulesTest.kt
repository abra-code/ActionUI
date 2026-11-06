package com.abracode.actionui.addon.hostsurface

import android.graphics.SurfaceTexture
import android.view.KeyEvent
import android.view.Surface
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The HostSurface rules on the JVM, with the registry and controllers driven directly (no views): binding
 * and replay, replacement order, a binding change inside a callback, hidden and zero-size suspension, a lost
 * Surface, release; then property parsing and the input tables.
 */
class HostSurfaceRulesTest {

    private class FakeHost(val log: MutableList<String>? = null) : HostSurfaceHost {
        var frames = 0
        val posted = mutableListOf<(Long) -> Unit>()
        override fun postFrame(onFrame: (Long) -> Unit) {
            frames += 1
            posted += onFrame
        }
        override fun cancelFrames() {}
        override fun applyCursor(cursor: HostSurfaceCursor) {}
        override fun giveUpFocus() {
            log?.add("giveUpFocus")
        }

        fun fireFrame(timeNanos: Long = 1_000_000_000L) {
            val callbacks = posted.toList()
            posted.clear()
            callbacks.forEach { it(timeNanos) }
        }
    }

    private class Recorder(val name: String, val log: MutableList<String>) : HostSurfaceDelegate {
        val events = mutableListOf<HostSurfaceEvent>()
        val ids = mutableListOf<Long>()
        var onEvent: ((HostSurfaceEvent) -> Unit)? = null
        override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
            events += event
            ids += info.surfaceID
            log += "$name $event"
            onEvent?.invoke(event)
        }
    }

    private val log = mutableListOf<String>()
    private lateinit var surface: Surface

    @Before
    fun setUp() {
        HostSurfaceRegistry.resetForTesting()
        surface = Surface(SurfaceTexture(false))
    }

    @After
    fun tearDown() {
        HostSurfaceRegistry.resetForTesting()
        assertEquals("no surface outlives a test", 0, HostSurfaceRegistry.liveCount)
    }

    private fun element(name: String = "viewport", viewID: Int = 5) =
        HostSurfaceController(name, "window", viewID, composited = false, sink = false, host = FakeHost())

    private fun bind(name: String, delegate: HostSurfaceDelegate?) =
        HostSurfaceRegistry.setBinding(name, delegate?.let { HostSurfaceBinding(it) })

    @Test
    fun createdNeedsASurfaceASizeAndAClient() {
        val client = Recorder("a", log)
        bind("viewport", client)
        val controller = element()
        assertEquals(listOf<HostSurfaceEvent>(), client.events)
        controller.surfaceAvailable(surface, 0, 0, 2f)
        assertEquals("no pixels yet", listOf<HostSurfaceEvent>(), client.events)
        controller.surfaceResized(200, 100)
        assertEquals(listOf(HostSurfaceEvent.CREATED), client.events)
    }

    @Test
    fun bindingReplaysAndReplacingDestroysTheOldOneFirst() {
        val controller = element()
        controller.surfaceAvailable(surface, 200, 100, 2f)
        val first = Recorder("first", log)
        val second = Recorder("second", log)
        bind("viewport", first)
        bind("viewport", second)
        assertEquals(listOf("first CREATED", "first DESTROYED", "second CREATED"), log)
        assertNotEquals("a new surfaceID with every CREATED", first.ids[0], second.ids[0])
        bind("viewport", null)
        assertEquals(listOf(HostSurfaceEvent.CREATED, HostSurfaceEvent.DESTROYED), second.events)
    }

    @Test
    fun aBindingChangeInsideACallbackWaitsForItsEnd() {
        val first = Recorder("first", log)
        val second = Recorder("second", log)
        first.onEvent = { event ->
            if (event == HostSurfaceEvent.CREATED) {
                bind("viewport", second)
                assertTrue("nothing reentrant", second.events.isEmpty())
            }
        }
        bind("viewport", first)
        element().surfaceAvailable(surface, 200, 100, 2f)
        assertEquals(listOf("first CREATED", "first DESTROYED", "second CREATED"), log)
    }

    @Test
    fun aBindingChangeInsideDestroyedDoesNotRecurse() {
        val first = Recorder("first", log)
        first.onEvent = { event ->
            if (event == HostSurfaceEvent.DESTROYED) {
                bind("viewport", null)
            }
        }
        val second = Recorder("second", log)
        bind("viewport", first)
        element().surfaceAvailable(surface, 200, 100, 2f)
        bind("viewport", second)
        // The change made inside DESTROYED (unbind) applies after the rebind: second is told, then unbound.
        assertEquals(listOf("first CREATED", "first DESTROYED", "second CREATED", "second DESTROYED"), log)
    }

    @Test
    fun aBindingChangeInsideDestroyedOfALostSurfaceWaitsForTheLoss() {
        val second = Recorder("second", log)
        val first = object : HostSurfaceDelegate, HostSurfaceRetirable {
            override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
                log += "first $event"
                if (event == HostSurfaceEvent.DESTROYED) {
                    bind("viewport", second)
                }
            }
            override fun retired() {
                log += "first retired"
            }
        }
        bind("viewport", first)
        val controller = element()
        controller.surfaceAvailable(surface, 200, 100, 2f)
        controller.surfaceLost()
        // One DESTROYED, then the retire; the dying Surface is not announced to the new client.
        assertEquals(listOf("first CREATED", "first DESTROYED", "first retired"), log)
        assertEquals(0L, controller.surfaceID)
        controller.surfaceAvailable(surface, 200, 100, 2f)
        assertEquals("first CREATED, first DESTROYED, first retired, second CREATED", log.joinToString())
    }

    @Test
    fun hiddenAndZeroSizeSuspendWithoutDestroying() {
        val client = Recorder("a", log)
        bind("viewport", client)
        val controller = element()
        controller.surfaceAvailable(surface, 200, 100, 2f)
        controller.setProperties(hidden = true, continuous = false)
        controller.setProperties(hidden = false, continuous = false)
        controller.surfaceResized(0, 100)
        controller.surfaceResized(300, 100)
        controller.surfaceResized(300, 100)
        assertEquals(
            listOf(
                HostSurfaceEvent.CREATED, HostSurfaceEvent.SUSPENDED, HostSurfaceEvent.RESUMED,
                HostSurfaceEvent.SUSPENDED, HostSurfaceEvent.CHANGED, HostSurfaceEvent.RESUMED,
            ),
            client.events,
        )
        assertEquals("one surface throughout", 1, client.ids.toSet().size)
    }

    @Test
    fun aLostSurfaceIsDestroyedAndANewOneIsANewSurface() {
        val client = Recorder("a", log)
        bind("viewport", client)
        val controller = element()
        controller.surfaceAvailable(surface, 200, 100, 2f)
        controller.surfaceLost()
        controller.surfaceAvailable(surface, 400, 200, 2f)
        assertEquals(listOf(HostSurfaceEvent.CREATED, HostSurfaceEvent.DESTROYED, HostSurfaceEvent.CREATED), client.events)
        assertNotEquals(client.ids[0], client.ids[2])
        controller.release()
        assertEquals(HostSurfaceEvent.DESTROYED, client.events.last())
        assertEquals(0, HostSurfaceRegistry.controllerCount)
        controller.surfaceAvailable(surface, 200, 100, 2f)
        assertEquals("a released controller announces nothing", 4, client.events.size)
    }

    @Test
    fun otherNamesAreNotTold() {
        val client = Recorder("a", log)
        bind("other", client)
        element().surfaceAvailable(surface, 200, 100, 2f)
        assertTrue(client.events.isEmpty())
    }

    @Test
    fun framesAreAskedForOnlyWhileOnScreen() {
        val host = FakeHost()
        val controller = HostSurfaceController("viewport", "window", 5, composited = false, sink = false, host = host)
        bind("viewport", Recorder("a", log))
        controller.surfaceAvailable(surface, 200, 100, 2f)
        controller.setProperties(hidden = true, continuous = true)
        assertEquals("no frame while suspended", 0, host.frames)
        controller.setProperties(hidden = false, continuous = true)
        assertEquals(1, host.frames)
    }

    @Test
    fun aFrameRequestedBeforeASuspensionComesAfterTheResume() {
        val host = FakeHost()
        val controller = HostSurfaceController("viewport", "window", 5, composited = false, sink = false, host = host)
        val frames = mutableListOf<Long>()
        bind("viewport", object : HostSurfaceDelegate {
            override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {}
            override fun onFrame(surfaceID: Long, frameTimeSeconds: Double) {
                frames += surfaceID
            }
        })
        controller.surfaceAvailable(surface, 200, 100, 2f)
        controller.requestFrame()
        controller.setProperties(hidden = true, continuous = false)
        // The vsync posted before the suspension fires while suspended: no frame, and the request stays.
        host.fireFrame()
        assertTrue("no frame while suspended", frames.isEmpty())
        controller.setProperties(hidden = false, continuous = false)
        host.fireFrame()
        assertEquals("the request is kept for after the resume", listOf(controller.surfaceID), frames)
    }

    @Test
    fun focusIsGivenUpBeforeDestroyed() {
        val host = FakeHost(log)
        val controller = HostSurfaceController("viewport", "window", 5, composited = false, sink = false, host = host)
        bind("viewport", Recorder("a", log))
        controller.surfaceAvailable(surface, 200, 100, 2f)
        controller.surfaceLost()
        assertEquals(listOf("a CREATED", "giveUpFocus", "a DESTROYED"), log)
    }

    // MARK: properties

    private fun props(json: String): HostSurfaceProperties =
        HostSurfaceProperties.parse(Json.parseToJsonElement(json) as JsonObject, null)

    @Test
    fun propertiesAndTheirDefaults() {
        assertEquals(HostSurfaceProperties(surfaceName = "viewport"), props("""{ "surfaceName": "viewport" }"""))
        val all = props(
            """{ "surfaceName": "s", "kind": "native", "continuous": true, "focusable": false, "opaque": false,
                "composited": true, "hidden": true, "idealWidth": 640, "idealHeight": 480.5 }""",
        )
        assertEquals(
            HostSurfaceProperties("s", null, continuous = true, focusable = false, opaque = false, composited = true,
                hidden = true, idealWidth = 640.0, idealHeight = 480.5),
            all,
        )
        val sink = props("""{ "surfaceName": "s", "kind": "sink" }""")
        assertEquals("a frame sink is supported", null, sink.unsupportedKind)
        assertTrue(sink.sink)
        assertEquals("gl", props("""{ "surfaceName": "s", "kind": "gl" }""").unsupportedKind)
        assertFalse(props("""{ "surfaceName": "s", "kind": "native" }""").sink)
        assertEquals(
            "ill-typed values fall back",
            HostSurfaceProperties(surfaceName = "s"),
            props("""{ "surfaceName": "s", "continuous": "yes", "idealWidth": -3, "focusable": "no" }"""),
        )
        assertEquals("", props("""{ "surfaceName": 5 }""").surfaceName)
    }

    // MARK: input tables

    @Test
    fun keyNamesModifiersAndText() {
        assertEquals("KeyA", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_A))
        assertEquals("KeyZ", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_Z))
        assertEquals("Digit0", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_0))
        assertEquals("Numpad9", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_NUMPAD_9))
        assertEquals("F12", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_F12))
        assertEquals("ArrowLeft", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_DPAD_LEFT))
        assertEquals("Backspace", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_DEL))
        assertEquals("ShiftRight", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_SHIFT_RIGHT))
        assertEquals("", HostSurfaceInputMapping.code(KeyEvent.KEYCODE_VOLUME_UP))
        assertEquals(
            HostModifiers.SHIFT or HostModifiers.META,
            HostSurfaceInputMapping.modifiers(KeyEvent.META_SHIFT_ON or KeyEvent.META_META_ON),
        )
        assertEquals("a", HostSurfaceInputMapping.insertableText('a'.code))
        assertNull("Escape", HostSurfaceInputMapping.insertableText(0x1B))
        assertNull("no character", HostSurfaceInputMapping.insertableText(0))
        // A right click as the emulator delivers it (dumpsys input): DOWN buttonState 0x2, UP buttonState 0x0.
        val secondary = android.view.MotionEvent.BUTTON_SECONDARY
        assertEquals(1, HostSurfaceInputMapping.button(HostSurfaceInputMapping.upButtonState(secondary, 0)))
        assertEquals(0, HostSurfaceInputMapping.button(HostSurfaceInputMapping.upButtonState(0, 0)))
        val upright = HostSurfaceInputMapping.tiltComponents(0f, 0f)
        assertEquals(0.0, upright.first, 1e-9)
        assertEquals(0.0, upright.second, 1e-9)
    }
}
