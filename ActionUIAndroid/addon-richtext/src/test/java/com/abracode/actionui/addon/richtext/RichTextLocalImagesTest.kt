package com.abracode.actionui.addon.richtext

import com.abracode.richtext.model.RichTextBlock
import com.abracode.richtext.model.RichTextDocument
import com.abracode.richtext.model.RichTextInline
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Local (file:) images in the Markdown: each is asked about by its path, and a refused one keeps its alt text but
 * loses its address; other images pass as they are. The same cases as the Swift RichTextLocalImagesTests.
 */
class RichTextLocalImagesTest {

    @Test fun aRefusedLocalImageLosesItsAddressOnly() {
        val markdown = """
            # ![a](file:///etc/hosts) heading

            ![b](https://example.com/b.png) ![c](data:image/png;base64,AA==) *![d](FILE:///tmp/x%20y.png)*

            > - [![e](file:///allowed/e.png)](https://example.com)

            | ![f](file:///etc/f.png) |
            |---|
            | ![g](file:///allowed/g.png) |
        """.trimIndent()
        val asked = mutableListOf<String>()
        val document = RichTextDocument.parse(markdown).keepingLocalImages { path ->
            asked.add(path)
            path.startsWith("/allowed/")
        }
        assertEquals(listOf("/etc/hosts", "/tmp/x y.png", "/allowed/e.png", "/etc/f.png", "/allowed/g.png"), asked)
        val images = document.blocks.flatMap { images(it) }
        assertEquals("every image keeps its alt text", listOf("a", "b", "c", "d", "e", "f", "g"), images.map { it.alt })
        assertEquals(
            listOf("", "https://example.com/b.png", "data:image/png;base64,AA==", "", "file:///allowed/e.png", "",
                "file:///allowed/g.png"),
            images.map { it.url },
        )
    }

    @Test fun aLocalAddressWithNoPathToAskAboutIsRefused() {
        val document = RichTextDocument.parse("![h](file://server/share/h.png)").keepingLocalImages { true }
        assertEquals(listOf(""), document.blocks.flatMap { images(it) }.map { it.url })
    }

    @Test fun markdownWithNoLocalImagesIsUnchanged() {
        val document = RichTextDocument.parse("Text, `code`, [a link](https://example.com) and ![x](https://example.com/x.png).")
        assertEquals(document, document.keepingLocalImages { false })
    }

    private fun images(block: RichTextBlock): List<RichTextInline.Image> = when (block) {
        is RichTextBlock.Heading -> block.inlines.flatMap { images(it) }
        is RichTextBlock.Paragraph -> block.inlines.flatMap { images(it) }
        is RichTextBlock.BlockQuote -> block.blocks.flatMap { images(it) }
        is RichTextBlock.ListBlock -> block.items.flatMap { item -> item.flatMap { images(it) } }
        is RichTextBlock.Table -> block.headers.flatMap { cell -> cell.flatMap { images(it) } } +
            block.rows.flatMap { row -> row.flatMap { cell -> cell.flatMap { images(it) } } }
        is RichTextBlock.CodeBlock, RichTextBlock.ThematicBreak -> emptyList()
    }

    private fun images(inline: RichTextInline): List<RichTextInline.Image> = when (inline) {
        is RichTextInline.Image -> listOf(inline)
        is RichTextInline.Emphasis -> inline.children.flatMap { images(it) }
        is RichTextInline.Strong -> inline.children.flatMap { images(it) }
        is RichTextInline.Strikethrough -> inline.children.flatMap { images(it) }
        is RichTextInline.Link -> inline.text.flatMap { images(it) }
        is RichTextInline.Text, is RichTextInline.Code, RichTextInline.LineBreak -> emptyList()
    }
}
