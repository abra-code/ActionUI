// RichText.cpp - WinUI's RichTextBlock for ActionUI's RichText add-on: one block of paragraphs, runs and links,
// its whole text selectable as one, built from the add-on's walk of the RichText model.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Text.h>
#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.UI.Text.h>

namespace docs = winrt::Microsoft::UI::Xaml::Documents;
namespace media = winrt::Microsoft::UI::Xaml::Media;

using namespace actionui_winui;

namespace {

// The paragraph runs go into: the block's last, or nullptr when it has none.
docs::Paragraph lastParagraph(muxc::RichTextBlock const &block) {
    auto blocks = block.Blocks();
    if (blocks.Size() == 0) {
        return nullptr;
    }
    return blocks.GetAt(blocks.Size() - 1).try_as<docs::Paragraph>();
}

// `element` (a Run or a Hyperlink) in `style` at `fontSize` (0: inherited).
void applyStyle(docs::TextElement const &element, uint32_t style, double fontSize) {
    if ((style & ActionUIWinUIRunBold) != 0) {
        element.FontWeight(winrt::Microsoft::UI::Text::FontWeights::Bold());
    }
    if ((style & ActionUIWinUIRunItalic) != 0) {
        element.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);
    }
    if ((style & ActionUIWinUIRunStrikethrough) != 0) {
        element.TextDecorations(winrt::Windows::UI::Text::TextDecorations::Strikethrough);
    }
    if ((style & ActionUIWinUIRunMonospace) != 0) {
        element.FontFamily(media::FontFamily(L"Cascadia Mono, Consolas"));
    }
    if (fontSize > 0) {
        element.FontSize(fontSize);
    }
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIRichTextBlockCreate(void) {
    return guardedObject("rich text block create", []() {
        muxc::RichTextBlock block;
        // Wrap, not WrapWholeWords: a word that does not fit breaks too, as SwiftUI's Text does.
        block.TextWrapping(mux::TextWrapping::Wrap);
        block.IsTextSelectionEnabled(true);
        return toObject(block);
    });
}

bool actionUIWinUIRichTextBlockClear(ActionUIWinUIObject *block) {
    return guarded("rich text block clear", [&]() {
        objectAs<muxc::RichTextBlock>(block, L"RichTextBlock").Blocks().Clear();
        return true;
    });
}

bool actionUIWinUIRichTextBlockSetFontSize(ActionUIWinUIObject *block, double fontSize) {
    return guarded("rich text block set font size", [&]() {
        muxc::RichTextBlock typed = objectAs<muxc::RichTextBlock>(block, L"RichTextBlock");
        if (fontSize > 0) {
            typed.FontSize(fontSize);
        } else {
            typed.ClearValue(muxc::RichTextBlock::FontSizeProperty());
        }
        return true;
    });
}

bool actionUIWinUIRichTextBlockAddParagraph(ActionUIWinUIObject *block, double indent, double firstLineIndent,
                                            double spaceBefore, double spaceAfter) {
    return guarded("rich text block add paragraph", [&]() {
        muxc::RichTextBlock typed = objectAs<muxc::RichTextBlock>(block, L"RichTextBlock");
        docs::Paragraph paragraph;
        paragraph.Margin(mux::Thickness{indent, spaceBefore, 0, spaceAfter});
        // WinUI takes a negative indent: the first line hangs (seen on Windows 11 with the Windows App SDK 2.7).
        paragraph.TextIndent(firstLineIndent);
        typed.Blocks().Append(paragraph);
        return true;
    });
}

bool actionUIWinUIRichTextBlockAddRun(ActionUIWinUIObject *block, const char *text, uint32_t style, double fontSize,
                                      const ActionUIWinUIColor *color, const char *themeBrush) {
    return guarded("rich text block add run", [&]() {
        docs::Paragraph paragraph = lastParagraph(objectAs<muxc::RichTextBlock>(block, L"RichTextBlock"));
        if (paragraph == nullptr) {
            return fail("rich text block add run", "the block has no paragraph");
        }
        docs::Run run;
        run.Text(toHString(text));
        applyStyle(run, style, fontSize);
        media::Brush brush = brushFor(color, themeBrush);
        if (brush != nullptr) {
            run.Foreground(brush);
        }
        paragraph.Inlines().Append(run);
        return true;
    });
}

bool actionUIWinUIRichTextBlockAddLineBreak(ActionUIWinUIObject *block) {
    return guarded("rich text block add line break", [&]() {
        docs::Paragraph paragraph = lastParagraph(objectAs<muxc::RichTextBlock>(block, L"RichTextBlock"));
        if (paragraph == nullptr) {
            return fail("rich text block add line break", "the block has no paragraph");
        }
        paragraph.Inlines().Append(docs::LineBreak());
        return true;
    });
}

bool actionUIWinUIRichTextBlockAddLink(ActionUIWinUIObject *block, const char *text, uint32_t style, double fontSize,
                                       ActionUIWinUICallback handler, void *context, ActionUIWinUICallback destroyContext) {
    return registerHandler("rich text block add link", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               docs::Paragraph paragraph =
                                   lastParagraph(objectAs<muxc::RichTextBlock>(block, L"RichTextBlock"));
                               if (paragraph == nullptr) {
                                   throw winrt::hresult_invalid_argument(L"the block has no paragraph");
                               }
                               docs::Hyperlink link;
                               docs::Run run;
                               run.Text(toHString(text));
                               // On the run, which takes every style (strikethrough included); the link gives
                               // its color and underline.
                               applyStyle(run, style, fontSize);
                               link.Inlines().Append(run);
                               // The handler decides what opens: no NavigateUri.
                               link.Click([holder](auto &&, auto &&) { holder->fire(); });
                               paragraph.Inlines().Append(link);
                           });
}

} // extern "C"
