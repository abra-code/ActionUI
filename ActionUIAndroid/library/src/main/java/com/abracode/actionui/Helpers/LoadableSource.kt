package com.abracode.actionui.Helpers

import kotlinx.serialization.json.JsonObject

/**
 * The serialized format of a loaded description, inferred from the source's file
 * extension. `.plist` selects [PLIST] (Apple binary/XML property list); anything
 * else - including no extension - is [JSON].
 *
 * On Android only [JSON] is decodable today: there is no built-in property-list
 * parser, so a [PLIST] source warn-and-skips (the same honest degrade pattern the
 * rest of the port uses). The enum is carried through so the deferred plist path
 * is explicit rather than silently misread as JSON.
 */
internal enum class LoadableFormat { JSON, PLIST }

/**
 * A `LoadableView` source string classified by *how* it must be fetched. Pure data
 * produced by [classifyLoadableSource]; the renderer ([com.abracode.actionui.Views.LoadableView])
 * turns each case into the actual read.
 *
 * The heuristics mirror Apple's `LoadableView.buildView`
 * (`ActionUI/Views/LoadableView.swift`): an `http://` / `https://` prefix is a
 * remote URL, a `file://` prefix or any string containing `/` is a filesystem
 * path, and anything else is a bundle resource name.
 */
internal sealed interface LoadableSource {
    /** No usable source (null / blank). Renders the "no source" placeholder. */
    object None : LoadableSource

    /** Bundle resource by [name] - read from the app's `assets/` on Android. */
    data class BundleName(val name: String, val format: LoadableFormat) : LoadableSource

    /** Absolute filesystem [path] (any `file://` scheme already stripped). */
    data class FilePath(val path: String, val format: LoadableFormat) : LoadableSource

    /**
     * Remote `http(s)` [url]. Deferred on Android (the synchronous local-source
     * chunk ships first; remote async loading lands with `RemoteLoadableView`),
     * so the renderer warn-and-skips this case.
     */
    data class Remote(val url: String, val format: LoadableFormat) : LoadableSource
}

/**
 * The effective source string for a `LoadableView`: the runtime [value] when set
 * and non-blank, else the first present and non-blank of `url` > `filePath` >
 * `name` from [properties]. Null when none is available. Mirrors the priority in
 * Apple's `LoadableView.initialValue`. Pure.
 */
internal fun resolveLoadableSource(value: String?, properties: JsonObject?): String? {
    if (!value.isNullOrBlank()) return value
    for (key in arrayOf("url", "filePath", "name")) {
        val candidate = properties?.stringProperty(key)
        if (!candidate.isNullOrBlank()) return candidate
    }
    return null
}

/**
 * Classifies [source] into a [LoadableSource] by Apple's heuristics (see that
 * type). A blank / null source is [LoadableSource.None]. The [LoadableFormat] is
 * read from the trailing extension (`.plist` -> [LoadableFormat.PLIST], else
 * [LoadableFormat.JSON]). Pure and unit-tested.
 */
internal fun classifyLoadableSource(source: String?): LoadableSource {
    val trimmed = source?.trim().orEmpty()
    if (trimmed.isEmpty()) return LoadableSource.None
    val lower = trimmed.lowercase()
    return when {
        lower.startsWith("http://") || lower.startsWith("https://") ->
            LoadableSource.Remote(trimmed, formatOf(trimmed))
        lower.startsWith("file://") -> {
            val path = trimmed.substring("file://".length)
            LoadableSource.FilePath(path, formatOf(path))
        }
        trimmed.contains('/') -> LoadableSource.FilePath(trimmed, formatOf(trimmed))
        else -> LoadableSource.BundleName(trimmed, formatOf(trimmed))
    }
}

/** [LoadableFormat] from a source's trailing extension; defaults to JSON. Pure. */
private fun formatOf(source: String): LoadableFormat =
    if (source.substringAfterLast('.', "").lowercase() == "plist") LoadableFormat.PLIST
    else LoadableFormat.JSON
