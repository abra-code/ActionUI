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
    return file.readText()
}
