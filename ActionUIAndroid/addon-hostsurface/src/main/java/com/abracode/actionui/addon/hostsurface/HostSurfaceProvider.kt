package com.abracode.actionui.addon.hostsurface

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri

/**
 * Self-registration hook: registers the `HostSurface` element when the app process starts, so a client only
 * links this module (the :map-osm pattern; see OsmMapProvider for why a ContentProvider). The provider serves
 * no data; every query method is a stub.
 */
class HostSurfaceProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        HostSurfaceElement.register()
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

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
