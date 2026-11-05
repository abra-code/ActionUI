package com.abracode.actionui.addontest

import android.graphics.Color
import android.graphics.Paint
import android.util.Log
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.addon.hostsurface.HostInputKind
import com.abracode.actionui.addon.hostsurface.HostSurfaceDelegate
import com.abracode.actionui.addon.hostsurface.HostSurfaceEvent
import com.abracode.actionui.addon.hostsurface.HostSurfaceInfo
import com.abracode.actionui.addon.hostsurface.HostSurfaceInput
import com.abracode.actionui.addon.hostsurface.HostSurfaces
import kotlin.math.cos

/**
 * The app side of the HostSurface demo (assets/HostSurface.json): a client that draws on the element's Surface
 * with a hardware Canvas, on the main thread, from frame callbacks. The background cycles while "continuous" is
 * on, and dragging leaves a trail of dots. It shows the client contract: keep the Surface from CREATED, stop at
 * SUSPENDED, let go of it at DESTROYED (synchronous), draw at onFrame. A native client (Vulkan, wgpu) does the
 * same with an ANativeWindow.
 */
object HostSurfaceDemoClient : HostSurfaceDelegate {
    private const val TAG = "HostSurfaceDemo"
    private val surfaces = HashMap<Long, HostSurfaceInfo>()
    private val suspended = HashSet<Long>()
    private val trail = ArrayList<Pair<Float, Float>>()
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }

    fun install() {
        HostSurfaces.setDelegate("demo.canvas", this)
        ActionUIModel.registerActionHandler("hostSurface.animate") { _, windowUUID, viewID, _, _ ->
            val on = ActionUIModel.getElementValue(windowUUID = windowUUID, viewID = viewID) as? Boolean ?: false
            ActionUIModel.setElementProperty(windowUUID, 90, "continuous", on)
        }
        ActionUIModel.registerActionHandler("hostSurface.hidden") { _, windowUUID, viewID, _, _ ->
            val on = ActionUIModel.getElementValue(windowUUID = windowUUID, viewID = viewID) as? Boolean ?: false
            ActionUIModel.setElementProperty(windowUUID, 90, "hidden", on)
        }
        ActionUIModel.registerActionHandler("hostSurface.padding") { _, windowUUID, viewID, _, _ ->
            val on = ActionUIModel.getElementValue(windowUUID = windowUUID, viewID = viewID) as? Boolean ?: false
            ActionUIModel.setElementProperty(windowUUID, 90, "padding", if (on) 24 else 0)
        }
    }

    override fun onSurface(event: HostSurfaceEvent, info: HostSurfaceInfo) {
        Log.i(TAG, "$event #${info.surfaceID} ${info.widthPixels}x${info.heightPixels} px, density ${info.density}")
        when (event) {
            HostSurfaceEvent.CREATED, HostSurfaceEvent.CHANGED -> {
                surfaces[info.surfaceID] = info
                HostSurfaces.requestFrame(info.surfaceID)
            }
            HostSurfaceEvent.SUSPENDED -> suspended += info.surfaceID
            HostSurfaceEvent.RESUMED -> {
                suspended -= info.surfaceID
                HostSurfaces.requestFrame(info.surfaceID)
            }
            HostSurfaceEvent.DESTROYED -> {
                surfaces.remove(info.surfaceID)
                suspended -= info.surfaceID
            }
        }
    }

    override fun onFrame(surfaceID: Long, frameTimeSeconds: Double) {
        val info = surfaces[surfaceID] ?: return
        if (surfaceID in suspended) {
            return
        }
        val canvas = try {
            info.surface.lockHardwareCanvas()
        } catch (error: IllegalStateException) {
            Log.w(TAG, "the surface cannot be drawn now: $error")
            return
        }
        try {
            val phase = (frameTimeSeconds % 6.0) / 6.0 * 2 * Math.PI
            canvas.drawRGB(
                (127 + 100 * cos(phase)).toInt(),
                (127 + 100 * cos(phase - 2.1)).toInt(),
                (127 + 100 * cos(phase + 2.1)).toInt(),
            )
            val radius = 8f * info.density
            for ((x, y) in trail) {
                canvas.drawCircle(x * info.density, y * info.density, radius, dot)
            }
        } finally {
            info.surface.unlockCanvasAndPost(canvas)
        }
    }

    override fun onInput(surfaceID: Long, event: HostSurfaceInput) {
        when (event.kind) {
            HostInputKind.POINTER_DOWN, HostInputKind.POINTER_DRAG -> {
                trail += event.x.toFloat() to event.y.toFloat()
                if (trail.size > 400) {
                    trail.removeAt(0)
                }
                HostSurfaces.requestFrame(surfaceID)
            }
            else -> Log.i(TAG, "input ${event.kind} ${event.code}")
        }
    }
}
