package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import com.abracode.actionui.Common.ActionUIConfiguration
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.resolvedOrigin
import com.abracode.actionui.Common.droppingUntypedElements
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.PlatformFilter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Reads a [LoadableSource] into a decoded [ActionUIElement], shared by both the
 * embedded [com.abracode.actionui.Views.LoadableView] element (which then *merges*
 * the result into the current window via
 * [com.abracode.actionui.Common.WindowModel.loadSubDescription]) and the top-level
 * [com.abracode.actionui.ActionUI.RenderSource] entry (which *replaces* the window
 * root via [com.abracode.actionui.Common.ActionUIModel.loadDescription]).
 *
 * The split mirrors Apple, where the same `FileLoadableView` / `RemoteLoadableView`
 * read a source and then branch on `isContentView` to pick
 * `loadDescription` (root) vs `loadSubViewDescription` (sub-view). Here the read +
 * decode is the shared part; the *registration policy* stays at the two call
 * sites. These functions register nothing themselves.
 */

/** Connect / read timeout (ms) for a remote `url` fetch. */
internal const val LOADABLE_REMOTE_TIMEOUT_MS = 15_000

/**
 * The longest a whole remote load may take, in milliseconds, as on Apple and Linux: a server sending a
 * byte now and then stays under the read timeout. The configuration's maximumDownloadTime, at least 1 ms;
 * null: no limit.
 */
internal val loadableRemoteTotalTimeoutMs: Long?
    get() = ActionUIConfiguration.current.limits.maximumDownloadTime?.let { seconds ->
        kotlin.math.ceil(seconds * 1000).coerceIn(1.0, Long.MAX_VALUE.toDouble()).toLong()
    }

/**
 * One daemon thread that ends the remote loads that outlast their time ([withLoadDeadline]). A
 * canceled timer leaves the queue at once, not when its time would have come, so finished loads
 * do not keep their connections for two minutes.
 */
private val loadDeadlines = ScheduledThreadPoolExecutor(1) { task ->
    Thread(task, "ActionUI load deadline").apply { isDaemon = true }
}.apply { removeOnCancelPolicy = true }

/**
 * [body]'s result, with [connection] disconnected once the whole load has taken [limitMs] (null:
 * no limit): the connect and read timeouts apply to each step, so a server that sends its headers
 * or its body a byte at a time stays under them. The step the disconnect interrupts throws, and
 * the error says the time ran out. [connection] is always disconnected when this returns.
 */
internal fun <T> withLoadDeadline(
    connection: HttpURLConnection,
    url: String,
    limitMs: Long? = loadableRemoteTotalTimeoutMs,
    body: () -> T,
): T {
    val expired = AtomicBoolean(false)
    val seconds = limitMs?.let { if (it % 1000 == 0L) "${it / 1000}" else "${it / 1000.0}" }
    val timer = limitMs?.let {
        loadDeadlines.schedule({
            expired.set(true)
            connection.disconnect()
        }, it, TimeUnit.MILLISECONDS)
    }
    try {
        val result = body()
        if (expired.get()) throw IOException("loading $url took longer than $seconds seconds")
        return result
    } catch (e: Exception) {
        // Whatever the disconnect made the step throw, the time ran out: an IOException, which
        // the callers catch.
        if (expired.get()) throw IOException("loading $url took longer than $seconds seconds", e)
        throw e
    } finally {
        timer?.cancel(false)
        connection.disconnect()
    }
}

/**
 * How deep LoadableViews may nest: one whose LoadableViews around it already number this
 * many is refused (ActionUIConfiguration.limits.maximumNestingDepth, 16 by default).
 */
internal val loadableMaxNestingDepth: Int get() = ActionUIConfiguration.current.limits.maximumNestingDepth

/**
 * The text a LoadableView's [source] is known by when the nesting rule compares sources,
 * or null for no source: a remote URL as written, a file by its canonical path (symbolic
 * links resolved, `.` and `..` removed), an asset by the path it is opened with.
 */
internal fun loadableNestingKey(source: LoadableSource): String? = when (source) {
    is LoadableSource.None -> null
    is LoadableSource.Remote -> source.url
    is LoadableSource.FilePath -> "file:" + try {
        File(source.path).canonicalPath
    } catch (e: IOException) {
        File(source.path).absolutePath
    }
    is LoadableSource.BundleName -> "asset:" + loadableAssetPath(source.name)
}

/**
 * Why the source known as [key] ([loadableNestingKey]) must not load inside LoadableViews
 * showing [enclosing] (the outermost first), or null when it may. A document that loads
 * itself, directly or through others, would load without end: file and asset sources load
 * while the view is composed. Siblings showing the same source are not in [enclosing], so
 * they stay allowed. The same rule and words as Apple's `ActionUIDocumentLoader.nestingRefusal`.
 */
internal fun loadableNestingRefusal(key: String, enclosing: List<String>): String? = when {
    key in enclosing -> "it includes itself"
    enclosing.size >= loadableMaxNestingDepth -> "LoadableViews are nested more than $loadableMaxNestingDepth deep"
    else -> null
}

/** The `assets/` path a bundle [name] is opened with: `.json` appended when it has no extension. */
internal fun loadableAssetPath(name: String): String = if (name.contains('.')) name else "$name.json"

/**
 * The result of reading + decoding a source, independent of how the caller
 * registers it. ([DescriptionLoad.Loaded] carries the decoded root but has *not*
 * been added to any window.)
 */
internal sealed interface DescriptionLoad {
    /**
     * Parsed and decoded; ready for the caller to register and render. [finalURL]: for a remote
     * source, the address it finally came from after redirects, which decides its origin;
     * [origin]: the origin the caller resolved for it.
     */
    data class Loaded(
        val element: ActionUIElement,
        val finalURL: String? = null,
        val origin: JSONContentOrigin? = null,
    ) : DescriptionLoad
    /** A source was present but could not be read / parsed; [message] is user-facing. */
    data class Failed(val message: String) : DescriptionLoad
    /** No usable source. */
    object NoSource : DescriptionLoad
    /** A recognized but not-yet-supported source (`.plist`); [message] is user-facing. */
    data class Deferred(val message: String) : DescriptionLoad
}

/**
 * Reads and decodes a remote `http(s)` [source]. The blocking HTTP read runs on
 * [Dispatchers.IO]; the parse resumes on the caller's dispatcher (so a caller that
 * suspends on the main dispatcher can safely register the result on the main
 * thread).
 */
internal suspend fun loadRemoteDescription(
    source: LoadableSource.Remote,
    json: Json,
    logger: ActionUILogger,
): DescriptionLoad {
    if (source.format == LoadableFormat.PLIST) return deferredPlist(source.url, logger)
    val (text, finalURL) = try {
        withContext(Dispatchers.IO) { fetchRemoteText(source.url) }
    } catch (e: IOException) {
        logger.log("LoadableLoader: failed to fetch '${source.url}': ${e.message}", LoggerLevel.error)
        return DescriptionLoad.Failed("Failed to load: ${source.url}")
    }
    val decoded = decodeDescription(text, json, logger)
    return if (decoded is DescriptionLoad.Loaded) decoded.copy(finalURL = finalURL) else decoded
}

/**
 * The origin of remote ActionUI JSON loaded from [source] inside [parent] into the LoadableView
 * [parentID], by the address it finally came from ([finalURL], after redirects; the requested
 * one when the load reported none): a trusted server that redirects elsewhere does not make the
 * other server's JSON trusted.
 */
internal fun remoteOrigin(
    source: LoadableSource.Remote,
    finalURL: String?,
    parent: JSONContentOrigin?,
    parentID: Int?,
): JSONContentOrigin? = resolvedOrigin(source.copy(url = finalURL ?: source.url), parent, parentID)

/**
 * Reads and decodes a local [source] (bundle `name` from [assets], or a
 * `filePath`). Synchronous IO, matching Apple's `FileLoadableView`. A
 * [LoadableSource.Remote] is handled by [loadRemoteDescription] and never reaches
 * here (defensive [DescriptionLoad.NoSource]).
 */
internal fun loadLocalDescription(
    source: LoadableSource,
    assets: AssetManager,
    json: Json,
    logger: ActionUILogger,
): DescriptionLoad = when (source) {
    is LoadableSource.None -> DescriptionLoad.NoSource
    is LoadableSource.Remote -> DescriptionLoad.NoSource // unreachable: remote loads async

    is LoadableSource.BundleName -> {
        if (source.format == LoadableFormat.PLIST) deferredPlist(source.name, logger)
        else {
            val path = loadableAssetPath(source.name)
            try {
                val text = assets.open(path).bufferedReader().use { it.readText() }
                decodeDescription(text, json, logger)
            } catch (e: IOException) {
                logger.log("LoadableLoader: bundle resource '$path' not found in assets/: ${e.message}", LoggerLevel.error)
                DescriptionLoad.Failed("Resource '${source.name}' not found")
            }
        }
    }

    is LoadableSource.FilePath -> {
        if (source.format == LoadableFormat.PLIST) deferredPlist(source.path, logger)
        else try {
            // Only a regular file: a device or a named pipe the document names would never
            // finish (or never start) reading on the main thread.
            val text = readRegularFileText(source.path)
            decodeDescription(text, json, logger)
        } catch (e: NotARegularFileException) {
            logger.log("LoadableLoader: not reading '${source.path}': ${e.message}", LoggerLevel.error)
            DescriptionLoad.Failed(e.message ?: "Cannot read file: ${source.path}")
        } catch (e: IOException) {
            logger.log("LoadableLoader: cannot read file '${source.path}': ${e.message}", LoggerLevel.error)
            DescriptionLoad.Failed("Cannot read file: ${source.path}")
        }
    }
}

/** The deepest nesting of arrays and objects a description may have: Apple's `JSONParser.maximumDepth`. */
internal const val DESCRIPTION_MAX_NESTING_DEPTH = 512

/**
 * Whether [text]'s arrays and objects nest deeper than [limit], counted outside strings
 * without parsing. The JSON parser and the platform filter recurse once per level, so
 * deeper text would end in a StackOverflowError, which no caller catches.
 */
internal fun jsonNestsDeeperThan(text: String, limit: Int): Boolean {
    var depth = 0
    var inString = false
    var escaped = false
    for (c in text) {
        if (inString) {
            if (escaped) escaped = false
            else if (c == '\\') escaped = true
            else if (c == '"') inString = false
        } else when (c) {
            '"' -> inString = true
            '[', '{' -> if (++depth > limit) return true
            ']', '}' -> depth--
        }
    }
    return false
}

/**
 * The largest ActionUI JSON, in UTF-8 bytes, ActionUI decodes: from the host, a file or a server
 * (ActionUIConfiguration.limits.maximumJSONSize, 16 MB by default).
 */
internal val descriptionMaxBytes: Int get() = ActionUIConfiguration.current.limits.maximumJSONSize

/** [descriptionMaxBytes] in whole megabytes, for messages. */
internal val descriptionMaxMegabytes: Int get() = descriptionMaxBytes / (1024 * 1024)

/** Whether [text] is longer than [limit] bytes in UTF-8, counted without encoding it. */
internal fun utf8LongerThan(text: String, limit: Int): Boolean {
    if (text.length > limit) return true
    var bytes = 0L
    var index = 0
    while (index < text.length) {
        val c = text[index]
        bytes += when {
            c.code < 0x80 -> 1
            c.code < 0x800 -> 2
            Character.isHighSurrogate(c) && index + 1 < text.length && Character.isLowSurrogate(text[index + 1]) -> { index++; 4 }
            else -> 3
        }
        if (bytes > limit) return true
        index++
    }
    return false
}

/** Decodes [text] through the Android [PlatformFilter] (same as the window root). */
internal fun decodeDescription(
    text: String,
    json: Json,
    logger: ActionUILogger,
): DescriptionLoad {
    val limit = descriptionMaxBytes
    if (utf8LongerThan(text, limit)) {
        logger.log("LoadableLoader: ActionUI JSON larger than $descriptionMaxMegabytes MB, not decoded", LoggerLevel.error)
        return DescriptionLoad.Failed("Larger than $descriptionMaxMegabytes MB")
    }
    if (jsonNestsDeeperThan(text, DESCRIPTION_MAX_NESTING_DEPTH)) {
        logger.log("LoadableLoader: description nested deeper than $DESCRIPTION_MAX_NESTING_DEPTH levels", LoggerLevel.error)
        return DescriptionLoad.Failed("Nested deeper than $DESCRIPTION_MAX_NESTING_DEPTH levels")
    }
    val element = try {
        val raw = json.parseToJsonElement(text)
        val filtered = PlatformFilter.Android.withLogger(logger).filter(raw)
        json.decodeFromJsonElement(ActionUIElement.serializer(), filtered).droppingUntypedElements(logger)
    } catch (e: SerializationException) {
        logger.log("LoadableLoader: failed to parse loaded description: ${e.message}", LoggerLevel.error)
        return DescriptionLoad.Failed("Failed to parse description")
    } catch (e: IllegalArgumentException) {
        logger.log("LoadableLoader: failed to decode loaded description: ${e.message}", LoggerLevel.error)
        return DescriptionLoad.Failed("Failed to decode description")
    }
    return DescriptionLoad.Loaded(element)
}

/**
 * Blocking GET of [url]'s body as text, with the address it finally came from after redirects
 * (HttpURLConnection follows them only within one scheme, so never from https to http). Call
 * only off the main thread.
 */
private fun fetchRemoteText(url: String): Pair<String, String> {
    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = LOADABLE_REMOTE_TIMEOUT_MS
        readTimeout = LOADABLE_REMOTE_TIMEOUT_MS
        requestMethod = "GET"
    }
    return withLoadDeadline(connection, url) {
        val code = connection.responseCode
        if (code !in 200..299) throw IOException("HTTP $code for $url")
        // Read up to the JSON size cap: a larger body is not decoded anyway, so reading on only costs memory.
        val limit = descriptionMaxBytes
        val buffer = ByteArrayOutputStream()
        connection.inputStream.use { input ->
            val chunk = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(chunk)
                if (count < 0) break
                buffer.write(chunk, 0, count)
                if (buffer.size() > limit) throw IOException("$url is larger than $descriptionMaxMegabytes MB")
            }
        }
        // After the body is read, the connection's URL is the last one it was redirected to.
        buffer.toString(Charsets.UTF_8.name()) to connection.url.toString()
    }
}

/** Warn-and-skip for a `.plist` source: no Android property-list parser yet. */
private fun deferredPlist(source: String, logger: ActionUILogger): DescriptionLoad {
    logger.log(
        "LoadableLoader: '.plist' sources are not supported on Android (no property-list parser); " +
            "use a JSON description. Source: $source",
        LoggerLevel.warning
    )
    return DescriptionLoad.Deferred("Property-list (.plist) sources are not supported on Android; use JSON")
}
