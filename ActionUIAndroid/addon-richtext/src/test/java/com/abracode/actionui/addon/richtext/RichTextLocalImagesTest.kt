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

    @Test fun relativeImagePathsResolveAgainstTheMarkdownsLocation() {
        val markdown = "![same](logo.png) ![sub](img/a.png) ![up](../../logo.png) ![web](https://example.com/w.png)"
        val asked = mutableListOf<String>()
        val document = richTextDocument(markdown, "file:///docs/guide/deep/README.md") { path ->
            asked.add(path)
            path != "/docs/logo.png"
        }
        // Resolved first, so the path that leaves the Markdown's folder is asked about like the others.
        assertEquals(listOf("/docs/guide/deep/logo.png", "/docs/guide/deep/img/a.png", "/docs/logo.png"), asked)
        assertEquals(
            listOf("file:///docs/guide/deep/logo.png", "file:///docs/guide/deep/img/a.png", "", "https://example.com/w.png"),
            document.blocks.flatMap { images(it) }.map { it.url },
        )
    }

    @Test fun withoutABaseARelativeImagePathStaysRelative() {
        val asked = mutableListOf<String>()
        val document = richTextDocument("![same](logo.png)", null) { asked.add(it); true }
        assertEquals(emptyList<String>(), asked)
        assertEquals(listOf("logo.png"), document.blocks.flatMap { images(it) }.map { it.url })
    }

    @Test fun theBaseUrlProperty() {
        assertEquals(null, markdownBaseUrl(null))
        assertEquals(null, markdownBaseUrl(""))
        assertEquals(null, markdownBaseUrl("javascript:alert(1)"))
        assertEquals("https://example.com/docs/", markdownBaseUrl("https://example.com/docs/"))
        assertEquals("file:/no/such/folder/README.md", markdownBaseUrl("/no/such/folder/README.md"))
        val folder = java.nio.file.Files.createTempDirectory("richtext").toFile()
        try {
            assertEquals(folder.toURI().toString(), markdownBaseUrl(folder.path))
            assertEquals(true, markdownBaseUrl(folder.path)!!.endsWith("/"))
        } finally {
            folder.delete()
        }
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
