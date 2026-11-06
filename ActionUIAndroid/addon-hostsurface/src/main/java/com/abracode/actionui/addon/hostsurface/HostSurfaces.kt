package com.abracode.actionui.addon.hostsurface

import android.os.Handler
import android.os.Looper
import android.view.Surface

/*
 The client side of the HostSurface element, the Android counterpart of the Apple add-on's C header
 (Add-ons/ActionUIHostSurface/Sources/CActionUIHostSurface/include/ActionUIHostSurface.h):

 - A client binds a [HostSurfaceDelegate] to the elements whose "surfaceName" is a name, before or after the
   document loads: [HostSurfaces.setDelegate]. Live surfaces are announced to it at once.
 - It gets CREATED (a Surface with a nonzero size), CHANGED (a new size), SUSPENDED and RESUMED (hidden, or a
   TextureView surface while the app is in the background), and DESTROYED (synchronous: stop all use of the
   Surface before returning). A replaced or unbound delegate gets DESTROYED first, and a surface's DESTROYED
   always comes before its successor's CREATED: a native window takes one producer at a time.
 - Every callback runs on the main thread. A delegate change made inside a callback takes effect when the
   outermost callback returns. [HostSurfaces.requestFrame] and [HostSurfaces.setContinuous] may be called from
   any thread and never wait.
 - Sizes are in pixels with the density beside them; positions in [HostSurfaceInput] are in points (dp), from
   the top-left corner, as on the other platforms.
*/

enum class HostSurfaceEvent { CREATED, CHANGED, SUSPENDED, RESUMED, DESTROYED }

/** The layout of the pixels given to [HostSurfaces.presentPixels]: 4 bytes per pixel, in this order. */
enum class HostPixelFormat {
    /** Blue, green, red, alpha; colors premultiplied by alpha. */
    BGRA8_PREMULTIPLIED,
    /** Red, green, blue, alpha; colors premultiplied by alpha. The surface's own layout: copied as is. */
    RGBA8_PREMULTIPLIED,
    /** Blue, green, red, unused: opaque. */
    BGRX8,
    /** Red, green, blue, unused: opaque. */
    RGBX8,
}

/** One announced surface. [surface] is valid until DESTROYED for [surfaceID] returns. */
class HostSurfaceInfo(
    /** Unique for the life of the process; a new one with every CREATED. */
    val surfaceID: Long,
    val windowUUID: String,
    val viewID: Int,
    val surface: Surface,
    val widthPixels: Int,
    val heightPixels: Int,
    /** Pixels per point (dp). */
    val density: Float,
    /** True for a TextureView ("composited": true), false for a SurfaceView. */
    val composited: Boolean,
    /**
     * True for a frame sink ("kind": "sink"): present finished pixels with [HostSurfaces.presentPixels] and do not
     * draw into [surface], which ActionUI then fills.
     */
    val frameSink: Boolean = false,
) {
    val widthPoints: Float get() = widthPixels / density
    val heightPoints: Float get() = heightPixels / density
}

enum class HostInputKind {
    POINTER_DOWN, POINTER_UP, POINTER_MOVE, POINTER_DRAG, POINTER_ENTER, POINTER_EXIT, POINTER_CANCEL,
    SCROLL, MAGNIFY, ROTATE, KEY_DOWN, KEY_UP, FOCUS_IN, FOCUS_OUT,
}

enum class HostPointerType { MOUSE, TOUCH, PEN }

enum class HostScrollUnit { POINTS, STEPS }

/** Modifier bits of [HostSurfaceInput.modifiers], the same values as the C header's. */
object HostModifiers {
    const val SHIFT = 1
    const val CONTROL = 2
    const val ALT = 4
    const val META = 8
    const val CAPS_LOCK = 16
}

/** The cursor over a surface (a mouse on Android), as the C header's AUIHostCursor values. */
enum class HostSurfaceCursor { ARROW, I_BEAM, CROSSHAIR, POINTING_HAND, OPEN_HAND, CLOSED_HAND, RESIZE_LEFT_RIGHT, RESIZE_UP_DOWN, NOT_ALLOWED, HIDDEN }

/** One input event, in points (dp) from the top-left corner of the surface. */
data class HostSurfaceInput(
    val kind: HostInputKind,
    val pointerType: HostPointerType = HostPointerType.TOUCH,
    /** 0 primary, 1 secondary, 2 middle. */
    val button: Int = 0,
    /** Stable per pointer while it lasts. */
    val pointerID: Long = 0,
    val modifiers: Int = 0,
    val clickCount: Int = 0,
    val x: Double = 0.0,
    val y: Double = 0.0,
    /** Scroll: how far the content should move, positive to the right and down, in [scrollUnit]. */
    val deltaX: Double = 0.0,
    val deltaY: Double = 0.0,
    val scrollUnit: HostScrollUnit = HostScrollUnit.POINTS,
    val pressure: Double = 0.0,
    val tiltX: Double = 0.0,
    val tiltY: Double = 0.0,
    /** The Android key code (KeyEvent.KEYCODE_*). */
    val keyCode: Int = 0,
    /** The W3C UI Events code of the key ("KeyA", "ArrowLeft"); empty when unknown. */
    val code: String = "",
    /** The text a key down produced, or null. */
    val text: String? = null,
    /** The event time in seconds, on the uptime clock. */
    val timestampSeconds: Double = 0.0,
)

/** A client of HostSurface elements. Every method runs on the main thread. */
interface HostSurfaceDelegate {
    fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo)

    /** [frameTimeSeconds]: the Choreographer frame time in seconds; use differences only. */
    fun onFrame(surfaceID: Long, frameTimeSeconds: Double) {}

    fun onInput(surfaceID: Long, event: HostSurfaceInput) {}
}

/** The client API. */
object HostSurfaces {
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    /**
     * Binds [delegate] (or, with null, unbinds) to every HostSurface element whose "surfaceName" is
     * [surfaceName], in every window, now and later. Main thread only; returns false elsewhere, or for an empty
     * name.
     */
    fun setDelegate(surfaceName: String, delegate: HostSurfaceDelegate?): Boolean {
        if (!isMainThread() || surfaceName.isEmpty()) {
            return false
        }
        HostSurfaceRegistry.setBinding(surfaceName, delegate?.let { HostSurfaceBinding(it) })
        return true
    }

    /** Asks for one onFrame at the next vsync. Any thread; never waits. Nothing once the surface is destroyed. */
    fun requestFrame(surfaceID: Long) {
        onMain { HostSurfaceRegistry.liveSurface(surfaceID)?.requestFrame() }
    }

    /** Frame callbacks at every vsync on or off, until the element's "continuous" changes. Any thread. */
    fun setContinuous(surfaceID: Long, continuous: Boolean) {
        onMain { HostSurfaceRegistry.liveSurface(surfaceID)?.setContinuousOverride(continuous) }
    }

    /** Sets the mouse pointer shape over the surface. Main thread only; false when the surface is not alive. */
    fun setCursor(surfaceID: Long, cursor: HostSurfaceCursor): Boolean {
        if (!isMainThread()) {
            return false
        }
        val controller = HostSurfaceRegistry.liveSurface(surfaceID) ?: return false
        controller.setCursor(cursor)
        return true
    }

    /**
     * Frame sink only ([HostSurfaceInfo.frameSink]): shows one finished frame, [height] rows of [width] pixels,
     * 4 bytes each in [format], [stride] bytes apart, scaled to the surface. The pixels are copied into the
     * surface's next buffer before it returns. Any thread; never waits for the main thread, but may wait briefly
     * for a free buffer when frames come faster than the display shows them. Returns false when the surface is not
     * a live frame sink (for example after its DESTROYED), when a size is 0, when [stride] is less than
     * [width] * 4, or when [pixels] is too short for the frame.
     */
    fun presentPixels(
        surfaceID: Long, pixels: ByteArray, width: Int, height: Int, stride: Int = width * 4,
        format: HostPixelFormat = HostPixelFormat.RGBA8_PREMULTIPLIED,
    ): Boolean {
        if (width <= 0 || height <= 0 || stride < width.toLong() * 4 ||
            pixels.size < stride.toLong() * (height - 1) + width.toLong() * 4 || !HostSurfaceNative.loaded) {
            return false
        }
        return HostSurfaceNative.nativePresentPixels(surfaceID, pixels, width, height, stride, format.ordinal + 1)
    }

    private fun onMain(work: () -> Unit) {
        if (isMainThread()) {
            work()
        } else {
            mainHandler.post(work)
        }
    }

    internal fun isMainThread(): Boolean = Looper.myLooper() == Looper.getMainLooper() && Looper.myLooper() != null
}
