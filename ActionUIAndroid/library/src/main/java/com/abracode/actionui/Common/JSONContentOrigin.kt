package com.abracode.actionui.Common

import androidx.compose.runtime.staticCompositionLocalOf
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.loadableAssetPath
import java.io.File
import java.io.IOException

/**
 * Where content came from, and how far it is trusted. ActionUI JSON that the host passes in, or
 * one in the app's resources (its assets, or a folder in the configuration's resourceFolder ([ActionUIConfiguration])),
 * is trusted; one a LoadableView loads from a server or from a file elsewhere is less
 * trusted, and so is anything inside it: [trust] is the lower of the source's own trust
 * and that of the content around it. Mirrors the Swift `JSONContentOrigin`.
 */
data class JSONContentOrigin(
    val source: Source,
    val trust: Trust,
    /** The LoadableView (its element id) this content was loaded into; null for a window's root, or a LoadableView with no id. */
    val parentID: Int?,
) {
    sealed interface Source {
        /** JSON or data the host passed in itself. */
        data object Host : Source
        /** A file in the app's resources: an asset by its path, or a file in a resource folder by its canonical path. */
        data class Resource(val path: String) : Source
        /** A local file anywhere else, by its canonical path. */
        data class File(val path: String) : Source
        /** An http or https address. */
        data class Remote(val url: String) : Source
    }

    enum class Trust { LESS_TRUSTED, TRUSTED }

    companion object {
        /** The host's own content. */
        val HOST = JSONContentOrigin(Source.Host, Trust.TRUSTED, null)
    }
}

/** The lower of two trusts. */
internal fun minTrust(a: JSONContentOrigin.Trust, b: JSONContentOrigin.Trust): JSONContentOrigin.Trust =
    if (a == JSONContentOrigin.Trust.TRUSTED && b == JSONContentOrigin.Trust.TRUSTED) JSONContentOrigin.Trust.TRUSTED else JSONContentOrigin.Trust.LESS_TRUSTED

/** Whether the canonical path [path] is inside [folder] (canonicalized), not [folder] itself. */
internal fun isFileInside(path: String, folder: String): Boolean {
    val base = try { File(folder).canonicalPath } catch (e: IOException) { return false }
    return path.startsWith(base.trimEnd(File.separatorChar) + File.separator)
}

/**
 * The origin of content loaded from [source] inside content of origin [parent] (null for a
 * window's root) into the LoadableView [parentID]; null for no source. An asset is a
 * resource; a file is one only inside one of [resourceFolders]; a remote address only when it is
 * one of [trustedOrigins] (https). Then the lower of that and [parent]'s trust, so a resource or a
 * trusted server that less-trusted content names stays less trusted.
 */
internal fun classifyOrigin(
    source: LoadableSource,
    parent: JSONContentOrigin?,
    parentID: Int?,
    resourceFolders: List<String>,
    trustedOrigins: List<String> = emptyList(),
): JSONContentOrigin? {
    val (kind, own) = when (source) {
        is LoadableSource.None -> return null
        is LoadableSource.BundleName ->
            JSONContentOrigin.Source.Resource(loadableAssetPath(source.name)) to JSONContentOrigin.Trust.TRUSTED
        is LoadableSource.FilePath -> {
            // A path that cannot be made canonical (where its ".." and links lead is unknown)
            // is never a resource.
            val canonical = try { File(source.path).canonicalPath } catch (e: IOException) { null }
            val path = canonical ?: File(source.path).absolutePath
            if (canonical != null && resourceFolders.any { isFileInside(canonical, it) }) {
                JSONContentOrigin.Source.Resource(path) to JSONContentOrigin.Trust.TRUSTED
            } else {
                JSONContentOrigin.Source.File(path) to JSONContentOrigin.Trust.LESS_TRUSTED
            }
        }
        is LoadableSource.Remote -> JSONContentOrigin.Source.Remote(source.url) to
            if (ActionUIConfiguration.isTrustedOrigin(source.url, trustedOrigins)) JSONContentOrigin.Trust.TRUSTED
            else JSONContentOrigin.Trust.LESS_TRUSTED
    }
    return JSONContentOrigin(kind, minTrust(own, parent?.trust ?: JSONContentOrigin.Trust.TRUSTED), parentID)
}

/**
 * The origin of the content a composable belongs to: the host's outside any LoadableView,
 * else that of the JSON the nearest LoadableView around it loaded. Renderers ask the
 * trust policy with this, so elements with no id (which have no view model) and template
 * rows are judged by the JSON they are in.
 */
val LocalJSONContentOrigin = staticCompositionLocalOf { JSONContentOrigin.HOST }
