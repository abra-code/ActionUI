package com.abracode.actionui.addon.hostsurface

import android.util.Log

/*
 The Kotlin side of libactionui_hostsurface.so (src/main/cpp/hostsurface_jni.c), which gives C, C++ and Rust
 clients the same C functions as on the other platforms (ActionUIHostSurface.h):
 - the C functions call the @JvmStatic methods here, which use the public API (HostSurfaces);
 - a C client is bound as a [NativeHostSurfaceDelegate], which forwards every callback to the client's C
   delegate (a native struct the library made; its address is [NativeHostSurfaceDelegate.handle]);
 - the struct is freed when the registry retires the binding (after its last DESTROYED).
 The enums' ordinals are the C values (plus one for the event and the input kind, which start at 1 there).
*/
internal object HostSurfaceNative {
    private const val TAG = "ActionUIHostSurface"

    /** The library, loaded at process start by the ContentProvider; false when it is not in the APK. */
    @Volatile
    var loaded = false
        private set

    fun load() {
        if (loaded) {
            return
        }
        loaded = try {
            System.loadLibrary("actionui_hostsurface")
            true
        } catch (error: UnsatisfiedLinkError) {
            Log.w(TAG, "libactionui_hostsurface.so is not loaded; C and Rust clients cannot bind: ${error.message}")
            false
        }
    }

    // MARK: called by the C functions

    @JvmStatic
    fun register() {
        HostSurfaceElement.register()
    }

    /** [handle] is the client's native struct, or 0 to unbind. False leaves the struct to the caller. */
    @JvmStatic
    fun setDelegate(surfaceName: String, handle: Long): Boolean =
        HostSurfaces.setDelegate(surfaceName, if (handle == 0L) null else NativeHostSurfaceDelegate(handle))

    @JvmStatic
    fun requestFrame(surfaceID: Long) {
        HostSurfaces.requestFrame(surfaceID)
    }

    @JvmStatic
    fun setContinuous(surfaceID: Long, continuous: Boolean) {
        HostSurfaces.setContinuous(surfaceID, continuous)
    }

    @JvmStatic
    fun setCursor(surfaceID: Long, cursor: Int): Boolean {
        val shape = HostSurfaceCursor.entries.getOrNull(cursor) ?: return false
        return HostSurfaces.setCursor(surfaceID, shape)
    }

    // MARK: frame sinks ("kind": "sink"), for every client

    /** Opens the frame-sink slot of a surface just announced. Main thread. */
    fun openSink(surfaceID: Long, surface: android.view.Surface) {
        if (loaded) {
            nativeSinkOpen(surfaceID, surface)
        }
    }

    /** Closes it before DESTROYED: later presents fail, and the shown frame is cleared. Main thread. */
    fun closeSink(surfaceID: Long) {
        if (loaded) {
            nativeSinkClose(surfaceID)
        }
    }

    @JvmStatic
    private external fun nativeSinkOpen(surfaceID: Long, surface: android.view.Surface)

    @JvmStatic
    private external fun nativeSinkClose(surfaceID: Long)

    /** actionUIHostSurfacePresentPixels; [format] is the C AUIHostPixelFormat value. */
    @JvmStatic
    external fun nativePresentPixels(
        surfaceID: Long, pixels: ByteArray, width: Int, height: Int, stride: Int, format: Int,
    ): Boolean

    // MARK: the client's C delegate

    @JvmStatic
    external fun nativeSurface(
        handle: Long, event: Int, surfaceID: Long, windowUUID: ByteArray, viewID: Int,
        surface: android.view.Surface, widthPixels: Int, heightPixels: Int, density: Float, frameSink: Boolean,
    )

    @JvmStatic
    external fun nativeFrame(handle: Long, surfaceID: Long, windowUUID: ByteArray, viewID: Int, seconds: Double)

    /**
     * [integers]: kind, pointerType, button, modifiers, clickCount, scrollUnit, scrollPhase, keyCode.
     * [doubles]: x, y, deltaX, deltaY, pressure, tiltX, tiltY, timestampSeconds, and two spare.
     */
    @JvmStatic
    external fun nativeInput(
        handle: Long, surfaceID: Long, windowUUID: ByteArray, viewID: Int, integers: IntArray, doubles: DoubleArray,
        pointerID: Long, code: ByteArray?, text: ByteArray?,
    )

    @JvmStatic
    external fun nativeFree(handle: Long)

    /** A C string: UTF-8 with a NUL at the end. */
    fun cString(text: String): ByteArray = text.toByteArray(Charsets.UTF_8) + 0
}

/** A C client bound through actionUIHostSurfaceSetDelegate. */
internal class NativeHostSurfaceDelegate(val handle: Long) : HostSurfaceDelegate, HostSurfaceRetirable {
    /** What frames and input need of each announced surface: the element's window and id. */
    private class Announced(val windowUUID: ByteArray, val viewID: Int)

    private val announced = HashMap<Long, Announced>()
    private var freed = false

    override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
        if (freed) {
            return
        }
        val element = announced.getOrPut(info.surfaceID) {
            Announced(HostSurfaceNative.cString(info.windowUUID), info.viewID)
        }
        if (event == HostSurfaceEvent.DESTROYED) {
            announced.remove(info.surfaceID)
        }
        HostSurfaceNative.nativeSurface(
            handle, event.ordinal + 1, info.surfaceID, element.windowUUID, element.viewID, info.surface,
            info.widthPixels, info.heightPixels, info.density, info.frameSink,
        )
    }

    override fun onFrame(surfaceID: Long, frameTimeSeconds: Double) {
        val element = announced[surfaceID] ?: return
        if (!freed) {
            HostSurfaceNative.nativeFrame(handle, surfaceID, element.windowUUID, element.viewID, frameTimeSeconds)
        }
    }

    override fun onInput(surfaceID: Long, event: HostSurfaceInput) {
        val element = announced[surfaceID] ?: return
        if (freed) {
            return
        }
        val integers = intArrayOf(
            event.kind.ordinal + 1, event.pointerType.ordinal, event.button, event.modifiers, event.clickCount,
            event.scrollUnit.ordinal, 0, event.keyCode,
        )
        val doubles = doubleArrayOf(
            event.x, event.y, event.deltaX, event.deltaY, event.pressure, event.tiltX, event.tiltY,
            event.timestampSeconds, 0.0, 0.0,
        )
        HostSurfaceNative.nativeInput(
            handle, surfaceID, element.windowUUID, element.viewID, integers, doubles, event.pointerID,
            HostSurfaceNative.cString(event.code), event.text?.let { HostSurfaceNative.cString(it) },
        )
    }

    /** The binding is gone and every surface it was told about got DESTROYED: free the client's struct. */
    override fun retired() {
        if (!freed) {
            freed = true
            HostSurfaceNative.nativeFree(handle)
        }
    }
}
