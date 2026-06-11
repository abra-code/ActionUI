package com.abracode.actionui.map.google

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Self-registration hook: registers [GoogleMapView] as the `Map` element
 * when the app process starts, so a client only has to LINK this module -
 * no code, no manual `ActionUIRegistry.register` call.
 *
 * Kotlin has no auto-running static constructor (a `companion object` init
 * block only runs when its class is first touched), so this uses Android's
 * canonical equivalent: a manifest-declared [ContentProvider], merged into
 * the app manifest by the manifest merger, whose [onCreate] the system
 * invokes at process start - before `Application.onCreate`, and therefore
 * before any document can reference a `Map`. The provider serves no data;
 * every query method is a stub. (androidx.startup exists for exactly this,
 * but it is one more dependency for one `register()` call.)
 */
class GoogleMapProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        GoogleMapView.register()
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
