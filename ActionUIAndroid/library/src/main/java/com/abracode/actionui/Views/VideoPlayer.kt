package com.abracode.actionui.Views

import android.net.Uri
import android.webkit.URLUtil
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.SystemSymbolIcon
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Video playback with transport controls. Mirror of the Apple `VideoPlayer`
 * element (`ActionUI/Views/VideoPlayer.swift`, AVKit's `VideoPlayer`),
 * rendered as the platform [android.widget.VideoView] with a [MediaController]
 * overlay through Compose's [AndroidView] interop - the `WebView` stance:
 * the OS ships a native video element, so no androidx.media3/ExoPlayer
 * dependency (what that would add, and the provider-module escape hatch if
 * demand appears, is in the porting notes).
 *
 * Sample JSON:
 * ```
 * {
 *   "type": "VideoPlayer",
 *   "id": 1,                                    // Positive id for the value bridge
 *   "properties": {
 *     "url": "https://example.com/video.mp4",   // Required: http(s):// or file://
 *                                               //   URL; error label if invalid/missing
 *     "autoplay": true,                         // Optional: start playback on appear
 *     "frame": { "height": 240 }                // A greedy element: bound its height
 *   }
 * }
 * ```
 *
 * **Value bridge** (Apple's, [ActionUIValueType.STRING]): the value is the
 * video URL. A host `setElementValue(...)` write swaps the video source at
 * runtime; the element never writes back (playback position is not observable
 * on the Apple side either).
 *
 * **`autoplay`** matches the Apple tri-state: `true` plays once the video is
 * prepared, `false` pauses explicitly, absent leaves the player idle awaiting
 * the user's transport controls (the same resting state as `false` here -
 * VideoView does not autoplay).
 *
 * **Controls.** The classic [MediaController] overlay (tap the video for
 * play/pause/seek), the platform counterpart of AVKit's built-in transport
 * controls.
 *
 * **Sizing.** Greedy like `Map` (AVKit's player fills whatever its parent
 * offers): declares `fillMaxSize`; the VideoView letterboxes the video to its
 * aspect ratio inside that box. Needs a bounded height (an explicit `frame`)
 * when hosted in an unbounded scroll column
 * ([[android-bounded-height-scroll]]).
 *
 * Remote URLs ride the existing `INTERNET` permission (entry 39). Cleartext
 * `http://` additionally needs the host to allow cleartext traffic, the
 * Android default-deny; prefer `https://`.
 */
object VideoPlayer : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.stringProperty("url") ?: ""

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val config = remember(element.properties) {
            resolveVideoPlayerConfig(element.properties, logger)
        }

        // The runtime value (a host write) overrides the static `url`, the
        // Apple precedence (`initialValue`: model.value, then the property).
        val urlString = (viewModel?.value as? String)?.takeIf { it.isNotEmpty() }
            ?: config.url.orEmpty()

        if (!URLUtil.isValidUrl(urlString)) {
            // Apple renders Label("Missing or invalid URL",
            // systemImage: "exclamationmark.triangle") here.
            remember(urlString) {
                logger.log("VideoPlayer missing or invalid URL, displaying error Label", LoggerLevel.error)
            }
            Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
                SystemSymbolIcon(
                    name = "exclamationmark.triangle",
                    explicitWeight = null,
                    explicitFill = null,
                    explicitGrade = null,
                    explicitSizeSp = null,
                    imageScale = null,
                    contentDescription = null,
                    logger = logger,
                )
                M3Text(
                    "Missing or invalid URL",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
            return
        }

        AndroidView(
            // A video player is greedy (AVKit's fills its proposal):
            // fillMaxSize, the Map/ShapeView stance, expanding through the
            // wrapContentSize a fixed frame applies.
            modifier = modifier.fillMaxSize(),
            factory = { context ->
                VideoView(context).apply {
                    setMediaController(MediaController(context).also { it.setAnchorView(this) })
                    setOnPreparedListener {
                        // Apple's tri-state autoplay: true plays, false/absent rests.
                        if (config.autoplay == true) start()
                    }
                    setOnErrorListener { _, what, extra ->
                        logger.log(
                            "VideoPlayer failed to play '${tag ?: urlString}' (error $what/$extra)",
                            LoggerLevel.error,
                        )
                        true // Swallow the platform's modal error dialog.
                    }
                }
            },
            // Runs on first composition and whenever the resolved URL changes
            // (a host write through the value bridge): (re)point the source.
            // The View's tag carries the URL it currently plays, so plain
            // recompositions don't restart playback.
            update = { view ->
                if (view.tag != urlString) {
                    view.tag = urlString
                    view.setVideoURI(Uri.parse(urlString))
                    if (config.autoplay != true) view.seekTo(1) // show the first frame, not black
                }
            },
            onRelease = { it.stopPlayback() },
        )
    }
}

// ---------------------------------------------------------------------------
// Pure configuration (internal so unit tests can reach it; nothing here
// touches android.widget, so the tests stay plain JVM).
// ---------------------------------------------------------------------------

/** The element's validated properties, resolved once per `properties` change. */
internal data class VideoPlayerConfig(
    val url: String? = null,
    /** Apple tri-state: `true` play / `false` pause / `null` leave idle. */
    val autoplay: Boolean? = null,
)

/**
 * Validates the VideoPlayer properties, warn-and-skip with Apple's messages
 * (`VideoPlayer.swift` `validateProperties`). Any *string* `url` is accepted
 * here - whether it is a loadable URL is the builder's runtime check, matching
 * Apple's `URL(string:)` split.
 */
internal fun resolveVideoPlayerConfig(props: JsonObject?, logger: ActionUILogger?): VideoPlayerConfig {
    if (props == null) return VideoPlayerConfig()

    val url = props["url"]?.let { raw ->
        if ((raw as? JsonPrimitive)?.isString != true) {
            logger?.log("VideoPlayer url must be a String; ignoring", LoggerLevel.error)
            null
        } else {
            raw.content
        }
    }

    val autoplay = props["autoplay"]?.let { raw ->
        val value = (raw as? JsonPrimitive)?.let { props.booleanProperty("autoplay") }
        if (value == null) {
            logger?.log(
                "Invalid type for VideoPlayer autoplay: expected Bool, ignoring",
                LoggerLevel.warning,
            )
        }
        value
    }

    return VideoPlayerConfig(url = url, autoplay = autoplay)
}
