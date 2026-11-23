package com.abracode.actionui.addon.richtext

import com.abracode.richtext.model.RichTextBlock
import com.abracode.richtext.model.RichTextDocument
import com.abracode.richtext.model.RichTextInline

// Local (file:) images in the element's Markdown, as the trust policy allows: the RichText library reads a file:
// image as given, so the element asks ActionUI first, as the built-in Image does for its file, and a refused image
// keeps its alt text but loses its address, which draws it as an image that cannot be loaded. The port of
// Add-ons/ActionUIRichText/Sources/RichText+LocalImages.swift.

/**
 * The document with every file: image whose path [reads] refuses left without an address; a file: address with no
 * path to ask about is refused too. Other images (web, data, and addresses the library refuses itself) are kept.
 */
internal fun RichTextDocument.keepingLocalImages(reads: (String) -> Boolean): RichTextDocument =
    RichTextDocument(blocks.map { it.keepingLocalImages(reads) })

private fun RichTextBlock.keepingLocalImages(reads: (String) -> Boolean): RichTextBlock = when (this) {
    is RichTextBlock.Heading -> copy(inlines = inlines.keepingLocalImages(reads))
    is RichTextBlock.Paragraph -> copy(inlines = inlines.keepingLocalImages(reads))
    is RichTextBlock.BlockQuote -> copy(blocks = blocks.map { it.keepingLocalImages(reads) })
    is RichTextBlock.ListBlock -> copy(items = items.map { item -> item.map { it.keepingLocalImages(reads) } })
    is RichTextBlock.Table -> copy(
        headers = headers.map { it.keepingLocalImages(reads) },
        rows = rows.map { row -> row.map { it.keepingLocalImages(reads) } },
    )
    is RichTextBlock.CodeBlock, RichTextBlock.ThematicBreak -> this
}

private fun List<RichTextInline>.keepingLocalImages(reads: (String) -> Boolean): List<RichTextInline> =
    map { it.keepingLocalImages(reads) }

private fun RichTextInline.keepingLocalImages(reads: (String) -> Boolean): RichTextInline = when (this) {
    is RichTextInline.Image -> {
        if (!url.startsWith("file:", ignoreCase = true)) {
            this
        } else {
            // The path the library would read: the file: URI's, percent escapes decoded.
            val path = try { java.io.File(java.net.URI(url)).path } catch (e: Exception) { null }
            if (path != null && reads(path)) this else copy(url = "")
        }
    }
    is RichTextInline.Emphasis -> copy(children = children.keepingLocalImages(reads))
    is RichTextInline.Strong -> copy(children = children.keepingLocalImages(reads))
    is RichTextInline.Strikethrough -> copy(children = children.keepingLocalImages(reads))
    is RichTextInline.Link -> copy(text = text.keepingLocalImages(reads))
    is RichTextInline.Text, is RichTextInline.Code, RichTextInline.LineBreak -> this
}
