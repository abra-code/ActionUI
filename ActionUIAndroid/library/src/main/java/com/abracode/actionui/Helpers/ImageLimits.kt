package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import java.util.Collections

/**
 * The largest image ActionUI decodes, in pixels: 64 megapixels, as on Apple and Linux. A larger
 * one (from a document, a file or a server) would take gigabytes of memory as a bitmap; its size
 * is read from its header first and it is not decoded.
 */
internal const val MAX_IMAGE_PIXELS = 64L * 1024 * 1024

/** Whether an image of [width] x [height] pixels is over [MAX_IMAGE_PIXELS] (in 64 bits). */
internal fun isTooLarge(width: Int, height: Int): Boolean =
    width.coerceAtLeast(0).toLong() * height.coerceAtLeast(0).toLong() > MAX_IMAGE_PIXELS

/** The sources already logged as over the cap (each once: a Canvas asks on every draw). */
private val loggedTooLarge: MutableSet<String> = Collections.synchronizedSet(mutableSetOf())

/** Whether the header [readBounds] fills declares too many pixels; logged once per [source]. */
private fun declaresTooManyPixels(source: String, logger: ActionUILogger?, readBounds: (BitmapFactory.Options) -> Unit): Boolean {
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    readBounds(options)
    if (!isTooLarge(options.outWidth, options.outHeight)) return false
    if (loggedTooLarge.add(source)) {
        logger?.log("Image not shown: $source is ${options.outWidth} x ${options.outHeight} pixels, more than $MAX_IMAGE_PIXELS", LoggerLevel.warning)
    }
    return true
}

/** The image file at [path], or null when it declares too many pixels or does not decode. */
internal fun decodeFileWithinCap(path: String, logger: ActionUILogger?): Bitmap? {
    if (declaresTooManyPixels(path, logger) { BitmapFactory.decodeFile(path, it) }) return null
    return BitmapFactory.decodeFile(path)
}

/** The image asset [name], or null when it declares too many pixels or does not decode (it may throw IOException, as opening it does). */
internal fun decodeAssetWithinCap(assets: AssetManager, name: String, logger: ActionUILogger?): Bitmap? {
    if (declaresTooManyPixels("asset $name", logger) { options -> assets.open(name).use { BitmapFactory.decodeStream(it, null, options) } }) return null
    return assets.open(name).use { BitmapFactory.decodeStream(it) }
}

/** The image in [bytes] (from [source]), or null when it declares too many pixels or does not decode. */
internal fun decodeBytesWithinCap(bytes: ByteArray, source: String, logger: ActionUILogger?): Bitmap? {
    if (declaresTooManyPixels(source, logger) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size, it) }) return null
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}
