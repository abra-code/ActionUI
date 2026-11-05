package com.abracode.actionui.addon.hostsurface

/*
 Sample JSON for HostSurface:
 {
   "type": "HostSurface",
   "id": 5,
   "properties": {
     "surfaceName": "viewport",   // Required: binds the element to the client set with HostSurfaces.setDelegate.
                                  //           Fixed at load.
     "kind": "native",            // Optional: "native" (default): an android.view.Surface. "sink" and "gl" are
                                  //           not available here: a placeholder is drawn. Fixed at load.
     "continuous": false,         // Optional: onFrame at every vsync while the surface is on screen.
     "focusable": true,           // Optional: a tap or click gives the surface keyboard focus; never at load.
     "opaque": true,              // Optional: false lets content behind show through (TextureView only).
     "composited": false,         // Optional: a TextureView instead of a SurfaceView: honors opacity and blends,
                                  //           but is not paced by the display. Fixed at load.
     "idealWidth": 320,           // Optional: width in points where the parent leaves it unbounded.
     "idealHeight": 240           // Optional: height in points where the parent leaves it unbounded.
   }
 }

 One AndroidView with no branches: a branch on any property would move the view to another composition group,
 and Compose would destroy the surface. Hidden is applied by the library's modifier chain (alpha 0); the element
 reads it to suspend the surface and to stop input. A SurfaceView's surface is destroyed by the platform when
 the app goes to the background or the activity is recreated (rotation): the client gets DESTROYED, then
 CREATED. A TextureView keeps its surface in the background and gets SUSPENDED instead.

 Size: the ideal size, within what the parent allows. ActionUI's stacks measure a child with a loose bound to
 learn its natural size, so a greedy element would take everything; "frame": { "maxWidth": "infinity" } (or
 maxHeight) makes it fill, as for any element. States: "size", [width, height] in points.
*/

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Choreographer
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.PointerIcon
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.viewinterop.AndroidView
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUIInputEnabled
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/** The element's own properties; ill-typed values warn and fall back to the default. Pure, for unit tests. */
internal data class HostSurfaceProperties(
    val surfaceName: String = "",
    /** null: "native"; else the unsupported kind. */
    val unsupportedKind: String? = null,
    val continuous: Boolean = false,
    val focusable: Boolean = true,
    val opaque: Boolean = true,
    val composited: Boolean = false,
    val hidden: Boolean = false,
    val idealWidth: Double = 320.0,
    val idealHeight: Double = 240.0,
) {
    companion object {
        fun parse(properties: JsonObject?, logger: ActionUILogger?): HostSurfaceProperties {
            fun warn(message: String) = logger?.log("HostSurface: $message", LoggerLevel.warning)
            fun bool(key: String, default: Boolean): Boolean {
                val raw = properties?.get(key) ?: return default
                val value = (raw as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
                if (value == null) {
                    warn("'$key' must be a Boolean, got $raw; using $default")
                }
                return value ?: default
            }
            fun number(key: String, default: Double): Double {
                val raw = properties?.get(key) ?: return default
                val value = (raw as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
                if (value == null || value < 0 || value.isNaN() || value.isInfinite()) {
                    warn("'$key' must be a number of zero or more, got $raw; using $default")
                    return default
                }
                return value
            }
            val nameRaw = properties?.get("surfaceName")
            val name = (nameRaw as? JsonPrimitive)?.takeIf { it.isString }?.content.orEmpty()
            if (name.isEmpty()) {
                warn("'surfaceName' is required and must be a non-empty String; no client can bind to this surface")
            }
            val kindRaw = properties?.get("kind")
            val unsupported = when {
                kindRaw == null -> null
                kindRaw is JsonPrimitive && kindRaw.isString && kindRaw.content == "native" -> null
                else -> {
                    val kind = (kindRaw as? JsonPrimitive)?.content ?: kindRaw.toString()
                    warn("kind '$kind' is not available on this platform; drawing a placeholder")
                    kind
                }
            }
            return HostSurfaceProperties(
                surfaceName = name,
                unsupportedKind = unsupported,
                continuous = bool("continuous", false),
                focusable = bool("focusable", true),
                opaque = bool("opaque", true),
                composited = bool("composited", false),
                hidden = bool("hidden", false),
                idealWidth = number("idealWidth", 320.0),
                idealHeight = number("idealHeight", 240.0),
            )
        }
    }
}

object HostSurfaceElement : ActionUIViewConstruction {
    private const val MAX_IDEAL_PIXELS = 100_000

    /** Registers the element; done at process start by [HostSurfaceProvider]. */
    fun register() {
        ActionUIRegistry.register("HostSurface", this)
    }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = remember(element.properties) { HostSurfaceProperties.parse(element.properties, logger) }
        val windowModel = LocalWindowModel.current
        val windowUUID = windowModel?.windowUUID.orEmpty()
        val viewModel = windowModel?.viewModels?.get(element.id)
        val density = LocalDensity.current.density
        val sized = modifier.layout { measurable, constraints ->
            // The ideal size, within the constraints (a frame that fills makes min equal max).
            // Capped well below what Constraints can hold, so a huge ideal size cannot break the layout.
            val width = (props.idealWidth * density).toInt().coerceAtMost(MAX_IDEAL_PIXELS)
                .coerceIn(constraints.minWidth, constraints.maxWidth)
            val height = (props.idealHeight * density).toInt().coerceAtMost(MAX_IDEAL_PIXELS)
                .coerceIn(constraints.minHeight, constraints.maxHeight)
            val placeable = measurable.measure(Constraints.fixed(width, height))
            layout(width, height) { placeable.place(0, 0) }
        }
        if (props.unsupportedKind != null) {
            Box(sized.background(Color.Gray.copy(alpha = 0.25f)), contentAlignment = Alignment.Center) {
                Text(props.surfaceName.ifEmpty { "HostSurface" }, color = Color.Gray)
            }
            return
        }
        // surfaceName and composited are fixed at load: the controller is made once per element.
        val controller = remember(windowUUID, element.id) {
            HostSurfaceViews.Holder(props.surfaceName, windowUUID, element.id, props.composited)
        }
        DisposableEffect(controller) {
            onDispose { controller.release() }
        }
        val inputEnabled = LocalActionUIInputEnabled.current && LocalActionUIEnabled.current
        AndroidView(
            modifier = sized.pointerInput(controller) {
                // The surface takes the wheel, so an enclosing ScrollView does not scroll too. The wheel comes
                // through Compose: once consumed here the View does not reliably see it.
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Main)
                        if (event.type != PointerEventType.Scroll || !controller.inputAllowed) {
                            continue
                        }
                        val change = event.changes.first()
                        // Compose's delta is how far to scroll (positive down for the wheel turned toward the
                        // user); the contract's is how far the content moves, the other way.
                        controller.controller?.deliverInput(
                            HostSurfaceInput(
                                kind = HostInputKind.SCROLL,
                                pointerType = HostPointerType.MOUSE,
                                x = (change.position.x / density).toDouble(),
                                y = (change.position.y / density).toDouble(),
                                deltaX = -change.scrollDelta.x.toDouble(),
                                deltaY = -change.scrollDelta.y.toDouble(),
                                scrollUnit = HostScrollUnit.STEPS,
                                timestampSeconds = change.uptimeMillis / 1000.0,
                            ),
                        )
                        event.changes.forEach { it.consume() }
                    }
                }
            },
            factory = { context -> controller.makeView(context) },
            update = { view ->
                controller.update(props, inputEnabled)
                (view as? TextureView)?.isOpaque = props.opaque
                if (!props.opaque && !props.composited && !controller.warnedOpaque) {
                    controller.warnedOpaque = true
                    logger.log(
                        "HostSurface: 'opaque' false needs 'composited' true on Android (a SurfaceView does not blend)",
                        LoggerLevel.warning,
                    )
                }
                controller.onSizeState = { widthPoints, heightPoints ->
                    viewModel?.states?.set("size", listOf(widthPoints, heightPoints))
                }
            },
            onRelease = { controller.release() },
        )
    }
}

/** The view side of one element: makes the SurfaceView or TextureView and feeds the controller. */
internal object HostSurfaceViews {

    class Holder(
        private val surfaceName: String,
        private val windowUUID: String,
        private val viewID: Int,
        private val composited: Boolean,
    ) : HostSurfaceHost {
        var controller: HostSurfaceController? = null
            private set
        private var view: View? = null
        private var focusable = true
        private var inputEnabled = true
        private var lastButtonState = 0
        var onSizeState: ((Double, Double) -> Unit)? = null
        var warnedOpaque = false

        /** Input reaches a client: one is bound (a surface is announced), enabled and not hidden. Without a
         * client the surface takes no touches, focus or keys, so it does not block an enclosing scroll view. */
        val inputAllowed: Boolean
            get() = inputEnabled && controller?.hidden == false && (controller?.surfaceID ?: 0L) != 0L

        fun makeView(context: Context): View {
            val made = HostSurfaceController(surfaceName, windowUUID, viewID, composited, this)
            controller = made
            val density = context.resources.displayMetrics.density
            val surfaceView = if (composited) makeTextureView(context, made, density) else makeSurfaceView(context, made, density)
            installInput(surfaceView, density)
            view = surfaceView
            return surfaceView
        }

        fun update(props: HostSurfaceProperties, inputEnabled: Boolean) {
            this.focusable = props.focusable
            this.inputEnabled = inputEnabled
            controller?.setProperties(props.hidden, props.continuous)
            val current = view ?: return
            // A hidden, disabled or non-focusable surface takes no focus, Tab included; turning it unfocusable
            // also drops the focus it has. Turning it focusable again leaves touch mode needing a tap.
            current.isFocusable = inputAllowed && focusable
        }

        fun release() {
            controller?.release()
            controller = null
        }

        private fun reportSize(width: Int, height: Int, density: Float) {
            onSizeState?.invoke((width / density).toDouble(), (height / density).toDouble())
        }

        private fun makeSurfaceView(context: Context, controller: HostSurfaceController, density: Float): View {
            val surfaceView = SurfaceView(context)
            surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) {
                    val frame = holder.surfaceFrame
                    controller.surfaceAvailable(holder.surface, frame.width(), frame.height(), density)
                    reportSize(frame.width(), frame.height(), density)
                }

                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                    controller.surfaceResized(width, height)
                    reportSize(width, height, density)
                }

                override fun surfaceDestroyed(holder: SurfaceHolder) {
                    // Synchronous: the client stops using the Surface before this returns.
                    controller.surfaceLost()
                }
            })
            return surfaceView
        }

        private fun makeTextureView(context: Context, controller: HostSurfaceController, density: Float): View {
            val textureView = object : TextureView(context) {
                // The TextureView keeps its surface in the background; the client is told to pause instead.
                override fun onWindowVisibilityChanged(visibility: Int) {
                    super.onWindowVisibilityChanged(visibility)
                    controller.setBackgrounded(visibility != View.VISIBLE)
                }
            }
            var surface: Surface? = null
            textureView.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                    val made = Surface(texture)
                    surface = made
                    controller.surfaceAvailable(made, width, height, density)
                    reportSize(width, height, density)
                }

                override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) {
                    controller.surfaceResized(width, height)
                    reportSize(width, height, density)
                }

                override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                    controller.surfaceLost()
                    surface?.release()
                    surface = null
                    return true
                }

                override fun onSurfaceTextureUpdated(texture: SurfaceTexture) {}
            }
            return textureView
        }

        // MARK: HostSurfaceHost

        private var frameCallback: Choreographer.FrameCallback? = null

        override fun postFrame(onFrame: (Long) -> Unit) {
            val callback = Choreographer.FrameCallback { frameTimeNanos ->
                frameCallback = null
                onFrame(frameTimeNanos)
            }
            frameCallback = callback
            Choreographer.getInstance().postFrameCallback(callback)
        }

        override fun cancelFrames() {
            frameCallback?.let { Choreographer.getInstance().removeFrameCallback(it) }
            frameCallback = null
        }

        override fun applyCursor(cursor: HostSurfaceCursor) {
            val current = view ?: return
            val type = when (cursor) {
                HostSurfaceCursor.ARROW -> PointerIcon.TYPE_ARROW
                HostSurfaceCursor.I_BEAM -> PointerIcon.TYPE_TEXT
                HostSurfaceCursor.CROSSHAIR -> PointerIcon.TYPE_CROSSHAIR
                HostSurfaceCursor.POINTING_HAND -> PointerIcon.TYPE_HAND
                HostSurfaceCursor.OPEN_HAND -> PointerIcon.TYPE_GRAB
                HostSurfaceCursor.CLOSED_HAND -> PointerIcon.TYPE_GRABBING
                HostSurfaceCursor.RESIZE_LEFT_RIGHT -> PointerIcon.TYPE_HORIZONTAL_DOUBLE_ARROW
                HostSurfaceCursor.RESIZE_UP_DOWN -> PointerIcon.TYPE_VERTICAL_DOUBLE_ARROW
                HostSurfaceCursor.NOT_ALLOWED -> PointerIcon.TYPE_NO_DROP
                HostSurfaceCursor.HIDDEN -> PointerIcon.TYPE_NULL
            }
            current.pointerIcon = PointerIcon.getSystemIcon(current.context, type)
        }

        override fun giveUpFocus() {
            val current = view ?: return
            if (current.hasFocus()) {
                // Unfocusable for a moment: that clears the focus (FOCUS_OUT through the listener) and keeps the
                // root from handing it straight back outside touch mode. In touch mode a tap focuses it again.
                current.isFocusable = false
                current.isFocusable = inputAllowed && focusable
            }
        }

        // MARK: input

        @SuppressLint("ClickableViewAccessibility")
        private fun installInput(view: View, density: Float) {
            // Not focusable in touch mode until a tap asks: Android gives a window's first focusable view focus
            // at load otherwise.
            view.isFocusable = true
            view.isFocusableInTouchMode = false
            view.setOnFocusChangeListener { _, hasFocus ->
                controller?.deliverInput(HostSurfaceInput(if (hasFocus) HostInputKind.FOCUS_IN else HostInputKind.FOCUS_OUT))
            }
            view.setOnTouchListener { touched, event ->
                if (!inputAllowed) {
                    return@setOnTouchListener false
                }
                if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                    // The drag is the surface's: an enclosing scroll container must not take it over (Compose's
                    // interop passes this on to its pointer input).
                    touched.parent?.requestDisallowInterceptTouchEvent(true)
                    if (focusable && !touched.hasFocus()) {
                        touched.isFocusableInTouchMode = true
                        touched.requestFocus()
                    }
                }
                // ACTION_UP carries the buttons still down, so the released one comes from the previous event.
                val inputs = HostSurfaceInputMapping.pointerEvents(event, density, lastButtonState)
                lastButtonState = event.buttonState
                for (input in inputs) {
                    controller?.deliverInput(input)
                }
                true
            }
            view.setOnGenericMotionListener { _, event ->
                // Hover from a mouse or a pen. The wheel comes through Compose (BuildView).
                if (!inputAllowed || event.actionMasked == MotionEvent.ACTION_SCROLL) {
                    return@setOnGenericMotionListener false
                }
                val inputs = HostSurfaceInputMapping.pointerEvents(event, density)
                for (input in inputs) {
                    controller?.deliverInput(input)
                }
                inputs.isNotEmpty()
            }
            view.setOnKeyListener { _, _, event ->
                // Tab moves focus on, as with any control.
                if (!inputAllowed || event.keyCode == KeyEvent.KEYCODE_TAB) {
                    return@setOnKeyListener false
                }
                val input = HostSurfaceInputMapping.keyEvent(event) ?: return@setOnKeyListener false
                controller?.deliverInput(input)
                // System keys (volume, media, Back, ...) are heard but not taken: the system still acts on them.
                !event.isSystem
            }
        }
    }
}
