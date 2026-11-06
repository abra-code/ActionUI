package com.abracode.actionui.addon.hostsurface

import android.view.Surface

/*
 The add-on's shared state and the lifecycle of one surface, kept free of views so the rules are unit-tested
 on the JVM (the element, HostSurfaceElement.kt, feeds a controller what its SurfaceView or TextureView
 reports). All of it runs on the main thread.

 The rules, as on Apple (Add-ons/ActionUIHostSurface/Sources/ActionUIHostSurface/HostSurfaceView.swift):
 - CREATED once there is a Surface with a nonzero size and a bound client; CHANGED for a new size;
   SUSPENDED and RESUMED as the element is hidden or (a TextureView) the app goes to the background and back;
   DESTROYED when the Surface goes away (synchronous), when the element goes away, and to the outgoing client
   when its name is bound to another.
 - A new surfaceID with every CREATED; DESTROYED goes to the client that got CREATED.
 - Every client callback goes through [HostSurfaceRegistry.deliver]: a binding change made inside one, or
   inside another binding change, is applied after the outermost one, in call order.
*/

/** One bound client; a class so a surface remembers which binding it announced itself to. */
internal class HostSurfaceBinding(val delegate: HostSurfaceDelegate)

/** A delegate told when its binding is gone for good: unbound or replaced, after its last DESTROYED. */
internal interface HostSurfaceRetirable {
    fun retired()
}

/** What a controller needs from the platform: frame callbacks, the pointer shape and keyboard focus. */
internal interface HostSurfaceHost {
    /** Calls [onFrame] with the frame time in nanoseconds at the next vsync, once. */
    fun postFrame(onFrame: (Long) -> Unit)
    fun cancelFrames()
    fun applyCursor(cursor: HostSurfaceCursor)
    /** Drops keyboard focus if the view has it; FOCUS_OUT reaches the client through the focus listener. */
    fun giveUpFocus()
}

internal object HostSurfaceRegistry {
    private val bindings = HashMap<String, HostSurfaceBinding>()
    private val controllers = LinkedHashSet<HostSurfaceController>()
    private val live = HashMap<Long, HostSurfaceController>()
    private var lastSurfaceID = 0L
    private var depth = 0
    private val pending = ArrayDeque<Pair<String, HostSurfaceBinding?>>()

    fun binding(name: String): HostSurfaceBinding? = bindings[name]

    fun setBinding(name: String, binding: HostSurfaceBinding?) {
        if (depth > 0) {
            pending.addLast(name to binding)
            return
        }
        val old = bindings[name]
        deliver {
            if (old != null) {
                for (controller in controllers.filter { it.surfaceName == name && it.announcedBinding === old }) {
                    controller.retract()
                }
            }
            if (binding == null) {
                bindings.remove(name)
            } else {
                bindings[name] = binding
            }
            for (controller in controllers.filter { it.surfaceName == name }) {
                controller.refresh()
            }
        }
        // Every surface it was told about got DESTROYED above, and nothing reaches it any more.
        if (old != null && old !== binding) {
            (old.delegate as? HostSurfaceRetirable)?.retired()
        }
    }

    /** Runs a client callback or a change that sends several; binding changes made inside wait for the end. */
    fun deliver(body: () -> Unit) {
        depth += 1
        try {
            body()
        } finally {
            depth -= 1
        }
        while (depth == 0 && pending.isNotEmpty()) {
            val (name, binding) = pending.removeFirst()
            setBinding(name, binding)
        }
    }

    fun add(controller: HostSurfaceController) {
        controllers.add(controller)
    }

    fun remove(controller: HostSurfaceController) {
        controllers.remove(controller)
    }

    fun announce(controller: HostSurfaceController): Long {
        lastSurfaceID += 1
        live[lastSurfaceID] = controller
        return lastSurfaceID
    }

    fun retire(surfaceID: Long) {
        live.remove(surfaceID)
    }

    fun liveSurface(surfaceID: Long): HostSurfaceController? = live[surfaceID]

    // For tests.
    val liveCount: Int get() = live.size
    val controllerCount: Int get() = controllers.size

    fun resetForTesting() {
        for (name in bindings.keys.toList()) {
            setBinding(name, null)
        }
        for (controller in controllers.toList()) {
            controller.release()
        }
        pending.clear()
    }
}

/** The lifecycle of one HostSurface element's surface. */
internal class HostSurfaceController(
    val surfaceName: String,
    val windowUUID: String,
    val viewID: Int,
    val composited: Boolean,
    /** "kind": "sink": the element opens a frame-sink slot for each announced surface (HostSurfaceNative). */
    val sink: Boolean,
    private val host: HostSurfaceHost,
) {
    var announcedBinding: HostSurfaceBinding? = null
        private set
    var surfaceID = 0L
        private set
    var suspendedSent = false
        private set

    private var surface: Surface? = null
    private var widthPixels = 0
    private var heightPixels = 0
    private var density = 1f
    private var announcedSize = 0 to 0

    var hidden = false
        private set
    private var backgrounded = false
    private var continuous = false
    private var continuousOverride: Boolean? = null
    private var framePending = false
    private var frameScheduled = false
    private var released = false

    var inputEnabled = true
    var focusable = true

    init {
        HostSurfaceRegistry.add(this)
    }

    // MARK: what the view reports

    fun surfaceAvailable(surface: Surface, width: Int, height: Int, density: Float) {
        this.surface = surface
        this.widthPixels = width
        this.heightPixels = height
        this.density = density
        refresh()
    }

    fun surfaceResized(width: Int, height: Int) {
        widthPixels = width
        heightPixels = height
        refresh()
    }

    /** The Surface is going away: DESTROYED now, before the platform takes it. */
    fun surfaceLost() {
        // In deliver, so a binding change made inside DESTROYED waits until the surface is gone: run earlier, it
        // would retract the surface a second time and announce the dying Surface to the new client.
        HostSurfaceRegistry.deliver {
            retract()
            surface = null
        }
    }

    fun setProperties(hidden: Boolean, continuous: Boolean) {
        if (continuous != this.continuous) {
            continuousOverride = null
        }
        this.hidden = hidden
        this.continuous = continuous
        refresh()
    }

    fun setBackgrounded(backgrounded: Boolean) {
        this.backgrounded = backgrounded
        refresh()
    }

    /** The element is gone. */
    fun release() {
        if (released) {
            return
        }
        HostSurfaceRegistry.deliver {
            retract()
            released = true
            host.cancelFrames()
            HostSurfaceRegistry.remove(this)
        }
    }

    // MARK: events

    private val shouldSuspend: Boolean
        get() = hidden || (composited && backgrounded) || widthPixels <= 0 || heightPixels <= 0

    fun refresh() {
        if (released) {
            return
        }
        val current = surface
        if (surfaceID == 0L) {
            val binding = HostSurfaceRegistry.binding(surfaceName)
            if (binding == null || current == null || widthPixels <= 0 || heightPixels <= 0) {
                updateFrames()
                return
            }
            surfaceID = HostSurfaceRegistry.announce(this)
            if (sink) {
                HostSurfaceNative.openSink(surfaceID, current)
            }
            announcedBinding = binding
            announcedSize = widthPixels to heightPixels
            suspendedSent = false
            send(HostSurfaceEvent.CREATED)
        } else if (widthPixels > 0 && heightPixels > 0 && announcedSize != (widthPixels to heightPixels)) {
            announcedSize = widthPixels to heightPixels
            send(HostSurfaceEvent.CHANGED)
        }
        // A binding change inside a callback can retract the surface before this point.
        if (surfaceID != 0L && shouldSuspend != suspendedSent) {
            suspendedSent = !suspendedSent
            send(if (suspendedSent) HostSurfaceEvent.SUSPENDED else HostSurfaceEvent.RESUMED)
        }
        updateFrames()
    }

    /** DESTROYED to the client that got CREATED; the controller stays and may be announced again. */
    fun retract() {
        if (surfaceID == 0L) {
            return
        }
        // FOCUS_OUT before DESTROYED, as on Apple: a successor gets no keys before a tap gives it FOCUS_IN.
        host.giveUpFocus()
        if (sink) {
            // Before DESTROYED, as on Apple: presents fail from here on (one under way finishes first), and the
            // old client's last frame is cleared.
            HostSurfaceNative.closeSink(surfaceID)
        }
        send(HostSurfaceEvent.DESTROYED)
        HostSurfaceRegistry.retire(surfaceID)
        surfaceID = 0
        announcedBinding = null
        suspendedSent = false
        framePending = false
        continuousOverride = null
        updateFrames()
    }

    private fun info(): HostSurfaceInfo? {
        val current = surface ?: return null
        return HostSurfaceInfo(
            surfaceID, windowUUID, viewID, current, announcedSize.first, announcedSize.second, density, composited, sink,
        )
    }

    private fun send(event: HostSurfaceEvent) {
        val binding = announcedBinding ?: return
        val info = info() ?: return
        HostSurfaceRegistry.deliver { binding.delegate.onSurface(event, info) }
    }

    fun deliverInput(event: HostSurfaceInput) {
        val binding = announcedBinding ?: return
        if (surfaceID == 0L) {
            return
        }
        val id = surfaceID
        HostSurfaceRegistry.deliver { binding.delegate.onInput(id, event) }
    }

    // MARK: frames

    fun requestFrame() {
        framePending = true
        updateFrames()
    }

    fun setContinuousOverride(on: Boolean) {
        continuousOverride = on
        updateFrames()
    }

    private val wantsFrames: Boolean
        get() = surfaceID != 0L && !suspendedSent && ((continuousOverride ?: continuous) || framePending)

    private fun updateFrames() {
        if (wantsFrames && !frameScheduled) {
            frameScheduled = true
            host.postFrame(::tick)
        }
    }

    private fun tick(frameTimeNanos: Long) {
        frameScheduled = false
        val binding = announcedBinding
        if (surfaceID != 0L && !suspendedSent && binding != null) {
            // A vsync posted before a suspension can fire during it; the request then waits for the resume.
            framePending = false
            val id = surfaceID
            HostSurfaceRegistry.deliver { binding.delegate.onFrame(id, frameTimeNanos / 1e9) }
        }
        updateFrames()
    }

    fun setCursor(cursor: HostSurfaceCursor) {
        host.applyCursor(cursor)
    }
}
