package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.PlatformFilter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

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
 * The result of reading + decoding a source, independent of how the caller
 * registers it. ([DescriptionLoad.Loaded] carries the decoded root but has *not*
 * been added to any window.)
 */
internal sealed interface DescriptionLoad {
    /** Parsed and decoded; ready for the caller to register and render. */
    data class Loaded(val element: ActionUIElement) : DescriptionLoad
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
    val text = try {
        withContext(Dispatchers.IO) { fetchRemoteText(source.url) }
    } catch (e: IOException) {
        logger.log("LoadableLoader: failed to fetch '${source.url}': ${e.message}", LoggerLevel.error)
        return DescriptionLoad.Failed("Failed to load: ${source.url}")
    }
    return decodeDescription(text, json, logger)
}

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
            val path = if (source.name.contains('.')) source.name else "${source.name}.json"
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
            val text = File(source.path).readText()
            decodeDescription(text, json, logger)
        } catch (e: IOException) {
            logger.log("LoadableLoader: cannot read file '${source.path}': ${e.message}", LoggerLevel.error)
            DescriptionLoad.Failed("Cannot read file: ${source.path}")
        }
    }
}

/** Decodes [text] through the Android [PlatformFilter] (same as the window root). */
internal fun decodeDescription(
    text: String,
    json: Json,
    logger: ActionUILogger,
): DescriptionLoad {
    val element = try {
        val raw = json.parseToJsonElement(text)
        val filtered = PlatformFilter.Android.withLogger(logger).filter(raw)
        json.decodeFromJsonElement(ActionUIElement.serializer(), filtered)
    } catch (e: SerializationException) {
        logger.log("LoadableLoader: failed to parse loaded description: ${e.message}", LoggerLevel.error)
        return DescriptionLoad.Failed("Failed to parse description")
    } catch (e: IllegalArgumentException) {
        logger.log("LoadableLoader: failed to decode loaded description: ${e.message}", LoggerLevel.error)
        return DescriptionLoad.Failed("Failed to decode description")
    }
    return DescriptionLoad.Loaded(element)
}

/** Blocking GET of [url]'s body as text. Call only off the main thread. */
private fun fetchRemoteText(url: String): String {
    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = LOADABLE_REMOTE_TIMEOUT_MS
        readTimeout = LOADABLE_REMOTE_TIMEOUT_MS
        requestMethod = "GET"
    }
    try {
        val code = connection.responseCode
        if (code !in 200..299) throw IOException("HTTP $code for $url")
        return connection.inputStream.bufferedReader().use { it.readText() }
    } finally {
        connection.disconnect()
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
