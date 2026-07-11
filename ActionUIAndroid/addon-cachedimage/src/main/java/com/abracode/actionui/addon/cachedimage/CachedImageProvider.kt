package com.abracode.actionui.addon.cachedimage

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Self-registration hook: registers [CachedImageView] as the `CachedImage` element when the app
 * process starts, so a client only has to LINK this module - no code, no manual
 * `ActionUIRegistry.register` call.
 *
 * Kotlin has no auto-running static constructor, so this uses Android's canonical equivalent: a
 * manifest-declared [ContentProvider], merged into the app manifest, whose [onCreate] the system
 * invokes at process start - before `Application.onCreate`, and therefore before any document can
 * reference a `CachedImage`. The provider serves no data; every query method is a stub. This is the
 * Android analog of the Apple add-on's explicit `ActionUICachedImage.register()` launch call
 * (Apple has no guaranteed pre-main hook for a statically linked Swift type). Mirrors
 * `map-osm`'s `OsmMapProvider`.
 */
class CachedImageProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        CachedImageView.register()
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0
}
