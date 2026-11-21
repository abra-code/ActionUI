package com.abracode.actionui.Helpers

import java.io.File
import java.io.IOException

/**
 * A path a document names that is something other than a regular file once symbolic
 * links are followed: a folder, a device such as `/dev/zero`, a named pipe or a socket.
 * Reading one would never end (or never begin) on the thread that reads it. The Android
 * counterpart of Apple's `ActionUIDocumentLoader.NotARegularFile`, with the same message.
 */
internal class NotARegularFileException(val path: String) : IOException("$path is not a regular file")

/**
 * The text of the file at [path] (UTF-8), which must be a regular file once symbolic links
 * are followed; throws [NotARegularFileException] for anything else that exists, or the
 * read's own [IOException] (a missing file among them).
 */
internal fun readRegularFileText(path: String): String {
    val file = File(path)
    if (file.exists() && !file.isFile) throw NotARegularFileException(path)
    // A document larger than the cap is not decoded anyway (DESCRIPTION_MAX_BYTES).
    if (file.length() > DESCRIPTION_MAX_BYTES) throw IOException("$path is larger than 16 MB")
    return file.readText()
}

/**
 * The bytes of the file at [path], with the same rule as [readRegularFileText]: for an
 * AsyncImage `file://` URL, where `/dev/zero` would be read until memory runs out (an
 * OutOfMemoryError, which no `catch (e: Exception)` stops) and a named pipe would hold an
 * IO thread for good.
 */
internal fun readRegularFileBytes(path: String): ByteArray {
    val file = File(path)
    if (file.exists() && !file.isFile) throw NotARegularFileException(path)
    return file.readBytes()
}

/**
 * Whether [path] names a regular file once symbolic links are followed. For readers that
 * open the path themselves, such as `BitmapFactory.decodeFile` for an Image or Canvas
 * `filePath`: opening a named pipe nobody writes to never returns, on the main thread.
 */
internal fun isRegularFile(path: String): Boolean = File(path).isFile
