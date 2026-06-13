package com.abracode.actionui.Views

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image as FoundationImage
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LOADABLE_REMOTE_TIMEOUT_MS
import com.abracode.actionui.Helpers.SystemSymbolIcon
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Asynchronously loaded remote (or local-file) image. Mirror of the Apple
 * `AsyncImage` element (`ActionUI/Views/AsyncImage.swift`, SwiftUI
 * `AsyncImage`), implemented dependency-free: the fetch is the same
 * [HttpURLConnection] pattern as `Helpers/LoadableLoader.kt` (entry 39) on
 * [Dispatchers.IO], the decode is the platform [BitmapFactory] - deliberately
 * no Coil or other image library (see the porting notes for what that would
 * add and when to revisit).
 *
 * Sample JSON:
 * ```
 * {
 *   "type": "AsyncImage",
 *   "id": 1,                                   // Optional: id for the value bridge
 *   "properties": {
 *     "url": "https://example.com/pic.png",    // String: http(s):// or file:// URL
 *     "placeholder": "photo",                  // Optional: SF Symbol shown while
 *                                              //   loading / on failure; default "photo"
 *     "resizable": true,                       // Optional: default true
 *     "contentMode": "fit",                    // Optional: "fit" | "fill"; default "fit"
 *     "frame": { "width": 300, "height": 300 } // The usual sizing modifier
 *   }
 * }
 * ```
 *
 * **Phases** (SwiftUI `AsyncImagePhase` parity): while loading and on failure
 * the `placeholder` SF Symbol renders through the shared glyph helper
 * (`SystemSymbolIcon`, the same SF->Material path as `Image`'s `systemName`);
 * on success the bitmap renders. A missing/empty `url` warns and shows the
 * placeholder, like the Apple builder.
 *
 * **Value bridge.** The runtime value is the URL string ([ActionUIValueType.STRING]);
 * a host `setElementValue(...)` write overrides the static `url` and re-points
 * the image - the load restarts because the fetch is keyed on the resolved URL.
 *
 * **Sizing.** `resizable: true` (default) maps `contentMode` to
 * [ContentScale.Fit] / [ContentScale.Crop] ("fill" clips to bounds, SwiftUI's
 * `.fill` behavior); `resizable: false` draws at the bitmap's intrinsic size
 * ([ContentScale.None]), SwiftUI's non-resizable `Image`.
 *
 * **Caching.** Successful `http(s)` decodes land in an in-memory, byte-budgeted
 * LRU keyed by URL ([AsyncImageMemoryCache]; 1/8 of the max heap). A cache hit
 * renders immediately - no placeholder flash, no refetch when a lazy-list row
 * scrolls back in or the same URL appears twice. This is the parity move:
 * Apple's `AsyncImage` rides `URLSession.shared` and gets the default
 * `URLCache` for free, while Android's `HttpURLConnection` caches no response
 * bodies unless the app installs an `HttpResponseCache`. Failures are not
 * cached (a transient error retries on the next entry into composition);
 * `file://` reads are cheap and skip the cache.
 *
 * **Deliberate non-features vs. an image library** (fine for the element's
 * scope, the reason Coil exists for app-scale image lists): no disk tier, no
 * in-flight request de-duplication (two elements racing the same URL both
 * fetch; the second store wins harmlessly), and no downsampling - the full
 * bitmap is decoded. Remote URLs ride the existing `INTERNET` permission
 * (entry 39).
 */
object AsyncImage : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.stringProperty("url")

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val config = remember(props) { resolveAsyncImageConfig(props, logger) }

        // The runtime value (a host write) overrides the static `url`, Apple parity.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val urlString = (viewModel?.value as? String)?.takeIf { it.isNotEmpty() } ?: config.url

        if (urlString.isNullOrEmpty()) {
            remember(urlString) {
                logger.log(
                    "AsyncImage missing valid url, using placeholder '${config.placeholder}'",
                    LoggerLevel.warning
                )
            }
            Placeholder(config, modifier, logger)
            return
        }

        // Cached -> render immediately (no placeholder flash); else Empty ->
        // (fetch + decode off the main thread) -> Success / Failure. Keyed on
        // the resolved URL: a host write restarts the load.
        val phase by produceState<AsyncImagePhase>(
            initialValue = asyncImageCache.get(urlString)
                ?.let { AsyncImagePhase.Success(it) }
                ?: AsyncImagePhase.Empty,
            urlString,
        ) {
            val cached = asyncImageCache.get(urlString)
            if (cached != null) {
                value = AsyncImagePhase.Success(cached)
                return@produceState
            }
            value = AsyncImagePhase.Empty
            value = loadAsyncImage(urlString, logger)
        }

        when (val current = phase) {
            is AsyncImagePhase.Success -> FoundationImage(
                bitmap = current.bitmap,
                // accessibilityLabel arrives as semantics on [modifier] via the
                // shared pipeline (entry 47's one-owner rule).
                contentDescription = null,
                modifier = modifier,
                contentScale = when {
                    !config.resizable -> ContentScale.None
                    config.contentModeFill -> ContentScale.Crop
                    else -> ContentScale.Fit
                },
            )

            AsyncImagePhase.Empty, AsyncImagePhase.Failure ->
                Placeholder(config, modifier, logger)
        }
    }

    /** The loading/failure glyph - `placeholder` through the shared SF-symbol helper. */
    @Composable
    private fun Placeholder(config: AsyncImageConfig, modifier: Modifier, logger: ActionUILogger) {
        val rendered = SystemSymbolIcon(
            name = config.placeholder,
            explicitWeight = null,
            explicitFill = null,
            explicitGrade = null,
            explicitSizeSp = null,
            imageScale = null,
            contentDescription = null,
            modifier = modifier,
            logger = logger,
        )
        if (!rendered) {
            remember(config.placeholder) {
                logger.log(
                    "AsyncImage placeholder '${config.placeholder}' has no SF->Material " +
                        "mapping; nothing rendered while loading/failed.",
                    LoggerLevel.warning
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Pure configuration (internal for plain-JVM unit tests) and the loader.
// ---------------------------------------------------------------------------

/** The element's validated properties, resolved once per `properties` change. */
internal data class AsyncImageConfig(
    val url: String? = null,
    val placeholder: String = "photo",
    val resizable: Boolean = true,
    val contentModeFill: Boolean = false,
)

/** One load attempt's lifecycle, the analog of SwiftUI's `AsyncImagePhase`. */
internal sealed interface AsyncImagePhase {
    object Empty : AsyncImagePhase
    data class Success(val bitmap: ImageBitmap) : AsyncImagePhase
    object Failure : AsyncImagePhase
}

/**
 * Validates the AsyncImage properties, warn-and-skip with Apple's messages
 * (`AsyncImage.swift` `validateProperties`). Any *string* `url` is accepted -
 * even an unloadable one - because load failure is a runtime phase, not a
 * validation error, matching Apple.
 */
internal fun resolveAsyncImageConfig(props: JsonObject?, logger: ActionUILogger?): AsyncImageConfig {
    if (props == null) return AsyncImageConfig()

    fun string(key: String): String? {
        val raw = props[key] ?: return null
        if ((raw as? JsonPrimitive)?.isString != true) {
            logger?.log("Invalid type for AsyncImage $key: expected String, ignoring", LoggerLevel.warning)
            return null
        }
        return raw.content
    }

    val resizable = props["resizable"]?.let { raw ->
        val value = (raw as? JsonPrimitive)?.let { props.booleanProperty("resizable") }
        if (value == null) {
            logger?.log("Invalid type for AsyncImage resizable: expected Bool, ignoring", LoggerLevel.warning)
        }
        value
    } ?: true

    val contentMode = string("contentMode")?.let { mode ->
        if (mode in setOf("fit", "fill")) {
            mode
        } else {
            logger?.log("Invalid AsyncImage contentMode '$mode', ignoring", LoggerLevel.warning)
            null
        }
    }

    return AsyncImageConfig(
        url = string("url"),
        placeholder = string("placeholder") ?: "photo",
        resizable = resizable,
        contentModeFill = contentMode == "fill",
    )
}

/**
 * A byte-budgeted, least-recently-used in-memory cache. Built on
 * [LinkedHashMap]'s access order (dependency-free and plain-JVM testable,
 * unlike `android.util.LruCache`). Accesses refresh recency; inserting past
 * the budget evicts from the least recently used end. NOT thread-safe by
 * design: all access happens on the main thread (the `produceState` producer
 * and the post-[withContext] continuation), the same single-threaded stance
 * as `ActionUIModel`.
 */
internal class ByteBudgetLruCache<V : Any>(
    private val budgetBytes: Long,
    private val sizeOf: (V) -> Long,
) {
    private val entries = LinkedHashMap<String, V>(16, 0.75f, true)
    private var usedBytes = 0L

    fun get(key: String): V? = entries[key]

    fun put(key: String, value: V) {
        val size = sizeOf(value)
        if (size > budgetBytes) return // larger than the whole budget: never cache
        entries.remove(key)?.let { usedBytes -= sizeOf(it) }
        entries[key] = value
        usedBytes += size
        val eldest = entries.iterator()
        while (usedBytes > budgetBytes && eldest.hasNext()) {
            usedBytes -= sizeOf(eldest.next().value)
            eldest.remove()
        }
    }

    val size: Int get() = entries.size
}

/**
 * The process-wide AsyncImage cache: 1/8 of the max heap (the classic Android
 * image-cache budget; Apple's counterpart is `URLSession.shared`'s default
 * `URLCache`). An [ImageBitmap]'s cost is its ARGB_8888 pixel buffer.
 */
private val asyncImageCache = ByteBudgetLruCache<ImageBitmap>(
    budgetBytes = Runtime.getRuntime().maxMemory() / 8,
    sizeOf = { it.width.toLong() * it.height.toLong() * 4L },
)

/**
 * Fetches and decodes [url] off the main thread. Failures (unreachable host,
 * HTTP error, unsupported scheme, undecodable bytes) warn and resolve to
 * [AsyncImagePhase.Failure] - the placeholder, never a crash, matching Apple's
 * "invalid URLs are allowed" stance. Successful `http(s)` decodes are stored
 * in [asyncImageCache]; failures are not, so a transient error retries.
 */
private suspend fun loadAsyncImage(url: String, logger: ActionUILogger?): AsyncImagePhase {
    val bitmap = try {
        withContext(Dispatchers.IO) {
            val bytes = fetchImageBytes(url)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }
    } catch (e: Exception) {
        logger?.log("AsyncImage: failed to load '$url': ${e.message}", LoggerLevel.warning)
        return AsyncImagePhase.Failure
    }
    if (bitmap == null) {
        logger?.log("AsyncImage: '$url' did not decode as an image", LoggerLevel.warning)
        return AsyncImagePhase.Failure
    }
    val image = bitmap.asImageBitmap()
    // file:// reads are cheap; only the network path earns a cache slot.
    if (url.startsWith("http://") || url.startsWith("https://")) {
        asyncImageCache.put(url, image)
    }
    return AsyncImagePhase.Success(image)
}

/**
 * Blocking read of [url]'s bytes: `http(s)://` through the same
 * [HttpURLConnection] shape (and timeout) as `LoadableLoader`'s text fetch,
 * `file://` from disk. Call only off the main thread.
 */
private fun fetchImageBytes(url: String): ByteArray = when {
    url.startsWith("http://") || url.startsWith("https://") -> {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = LOADABLE_REMOTE_TIMEOUT_MS
            readTimeout = LOADABLE_REMOTE_TIMEOUT_MS
            requestMethod = "GET"
        }
        try {
            val code = connection.responseCode
            if (code !in 200..299) throw IOException("HTTP $code for $url")
            connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    url.startsWith("file://") -> File(URI(url)).readBytes()

    else -> throw IOException("unsupported URL (expected http(s):// or file://)")
}
