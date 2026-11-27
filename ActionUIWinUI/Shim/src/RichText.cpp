// RichText.cpp - WinUI's RichTextBlock for ActionUI's RichText add-on: one block of paragraphs, runs and links,
// its whole text selectable as one, built from the add-on's walk of the RichText model.

#include "ShimInternal.h"

#include <algorithm>
#include <cmath>

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

int32_t actionUIWinUIRichTextBlockLastInlineIndex(ActionUIWinUIObject *block) {
    int32_t index = -1;
    guarded("rich text block last inline index", [&]() {
        docs::Paragraph paragraph = lastParagraph(objectAs<muxc::RichTextBlock>(block, L"RichTextBlock"));
        uint32_t count = paragraph != nullptr ? paragraph.Inlines().Size() : 0;
        if (count == 0) {
            return fail("rich text block last inline index", "the last paragraph has no inline");
        }
        index = static_cast<int32_t>(count - 1);
        return true;
    });
    return index;
}

int32_t actionUIWinUIRichTextBlockInlineLineBounds(ActionUIWinUIObject *block, int32_t paragraphIndex,
                                                   int32_t inlineIndex, ActionUIWinUIRect *rects, int32_t capacity) {
    int32_t written = 0;
    guarded("rich text block inline line bounds", [&]() {
        muxc::RichTextBlock typed = objectAs<muxc::RichTextBlock>(block, L"RichTextBlock");
        auto blocks = typed.Blocks();
        if (rects == nullptr || capacity <= 0 || paragraphIndex < 0 ||
            static_cast<uint32_t>(paragraphIndex) >= blocks.Size()) {
            return fail("rich text block inline line bounds", "no such paragraph");
        }
        docs::Paragraph paragraph = blocks.GetAt(static_cast<uint32_t>(paragraphIndex)).try_as<docs::Paragraph>();
        if (paragraph == nullptr || inlineIndex < 0 || static_cast<uint32_t>(inlineIndex) >= paragraph.Inlines().Size()) {
            return fail("rich text block inline line bounds", "no such inline");
        }
        docs::TextElement element = paragraph.Inlines().GetAt(static_cast<uint32_t>(inlineIndex)).try_as<docs::TextElement>();
        if (element == nullptr) {
            return fail("rich text block inline line bounds", "no such inline");
        }
        // Each character between two positions inside the inline: from its leading edge (the position before it,
        // looking forward) to its trailing edge (the position after it, looking back), which are on the same line
        // even where the line wraps after it. Characters on one line make one rectangle.
        docs::TextPointer start = element.ContentStart();
        int32_t length = element.ContentEnd().Offset() - start.Offset();
        if (length <= 0) {
            return true;
        }
        // Nearly every inline is on one line: its first and last characters' edges then make its one rectangle.
        {
            docs::TextPointer last = start.GetPositionAtOffset(length - 1, docs::LogicalDirection::Forward);
            docs::TextPointer end = element.ContentEnd();
            if (last == nullptr) {
                return true;
            }
            wf::Rect first = start.GetCharacterRect(docs::LogicalDirection::Forward);
            wf::Rect lastLeading = last.GetCharacterRect(docs::LogicalDirection::Forward);
            wf::Rect trailing = end.GetCharacterRect(docs::LogicalDirection::Backward);
            if (!std::isfinite(first.X) || !std::isfinite(first.Y) || !std::isfinite(first.Height) ||
                !std::isfinite(lastLeading.Y) || !std::isfinite(trailing.X)) {
                return true;
            }
            if (std::abs(static_cast<double>(lastLeading.Y) - first.Y) < first.Height / 2) {
                double right = std::max(static_cast<double>(trailing.X), static_cast<double>(first.X));
                rects[written++] = ActionUIWinUIRect{first.X, first.Y, right - first.X, first.Height};
                return true;
            }
        }
        bool open = false;
        double left = 0, right = 0, top = 0, bottom = 0;
        auto finish = [&]() {
            if (open && written < capacity) {
                rects[written++] = ActionUIWinUIRect{left, top, right > left ? right - left : 0, bottom > top ? bottom - top : 0};
            }
            open = false;
        };
        for (int32_t index = 0; index < length && written < capacity; ++index) {
            docs::TextPointer before = start.GetPositionAtOffset(index, docs::LogicalDirection::Forward);
            docs::TextPointer after = start.GetPositionAtOffset(index + 1, docs::LogicalDirection::Backward);
            if (before == nullptr || after == nullptr) {
                break;
            }
            wf::Rect leading = before.GetCharacterRect(docs::LogicalDirection::Forward);
            wf::Rect trailing = after.GetCharacterRect(docs::LogicalDirection::Backward);
            // Rect.Empty (infinite) for text not laid out yet: nothing to draw.
            if (!std::isfinite(leading.X) || !std::isfinite(leading.Y) || !std::isfinite(leading.Height) ||
                !std::isfinite(trailing.X)) {
                written = 0;
                open = false;
                return true;
            }
            double characterTop = leading.Y;
            double characterBottom = static_cast<double>(leading.Y) + leading.Height;
            // A new line: its top below the current line's middle.
            if (open && characterTop >= (top + bottom) / 2) {
                finish();
            }
            if (!open) {
                open = true;
                left = leading.X;
                right = trailing.X;
                top = characterTop;
                bottom = characterBottom;
            } else {
                left = std::min(left, static_cast<double>(leading.X));
                right = std::max(right, static_cast<double>(trailing.X));
                top = std::min(top, characterTop);
                bottom = std::max(bottom, characterBottom);
            }
        }
        finish();
        return true;
    });
    return written;
}

bool actionUIWinUIRichTextBlockParagraphBounds(ActionUIWinUIObject *block, int32_t index, ActionUIWinUIRect *bounds) {
    return guarded("rich text block paragraph bounds", [&]() {
        muxc::RichTextBlock typed = objectAs<muxc::RichTextBlock>(block, L"RichTextBlock");
        auto blocks = typed.Blocks();
        if (bounds == nullptr || index < 0 || static_cast<uint32_t>(index) >= blocks.Size()) {
            return fail("rich text block paragraph bounds", "no such paragraph");
        }
        docs::Paragraph paragraph = blocks.GetAt(static_cast<uint32_t>(index)).try_as<docs::Paragraph>();
        if (paragraph == nullptr) {
            return fail("rich text block paragraph bounds", "no such paragraph");
        }
        wf::Rect first = paragraph.ContentStart().GetCharacterRect(docs::LogicalDirection::Forward);
        wf::Rect last = paragraph.ContentEnd().GetCharacterRect(docs::LogicalDirection::Backward);
        // Rect.Empty (infinite) for text not laid out yet.
        if (!std::isfinite(first.Y) || !std::isfinite(last.Y) || !std::isfinite(last.Height)) {
            return fail("rich text block paragraph bounds", "the paragraph is not laid out");
        }
        double left = paragraph.Margin().Left;
        double top = first.Y;
        double bottom = static_cast<double>(last.Y) + last.Height;
        bounds->x = left;
        bounds->y = top;
        bounds->width = typed.ActualWidth() > left ? typed.ActualWidth() - left : 0;
        bounds->height = bottom > top ? bottom - top : 0;
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

bool actionUIWinUIRichTextBlockAddParagraph(ActionUIWinUIObject *block, double indent, double rightIndent,
                                            double firstLineIndent, double spaceBefore, double spaceAfter) {
    return guarded("rich text block add paragraph", [&]() {
        muxc::RichTextBlock typed = objectAs<muxc::RichTextBlock>(block, L"RichTextBlock");
        docs::Paragraph paragraph;
        paragraph.Margin(mux::Thickness{indent, spaceBefore, rightIndent, spaceAfter});
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

bool actionUIWinUIRichTextBlockAddSpacer(ActionUIWinUIObject *block, double width) {
    return guarded("rich text block add spacer", [&]() {
        if (!(width >= 0 && width < 1000000.0)) {
            return fail("rich text block add spacer", "the width must be 0 or more, and finite");
        }
        docs::Paragraph paragraph = lastParagraph(objectAs<muxc::RichTextBlock>(block, L"RichTextBlock"));
        if (paragraph == nullptr) {
            return fail("rich text block add spacer", "the block has no paragraph");
        }
        muxc::Border space;
        space.Width(width);
        space.Height(0);
        space.IsHitTestVisible(false);
        docs::InlineUIContainer container;
        container.Child(space);
        paragraph.Inlines().Append(container);
        return true;
    });
}

bool actionUIWinUIRichTextBlockAddInlineElement(ActionUIWinUIObject *block, ActionUIWinUIObject *element) {
    return guarded("rich text block add inline element", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        docs::Paragraph paragraph = lastParagraph(objectAs<muxc::RichTextBlock>(block, L"RichTextBlock"));
        if (paragraph == nullptr) {
            return fail("rich text block add inline element", "the block has no paragraph");
        }
        if (media::VisualTreeHelper::GetParent(typed) != nullptr) {
            return fail("rich text block add inline element", "the element has a parent");
        }
        docs::InlineUIContainer container;
        container.Child(typed);
        paragraph.Inlines().Append(container);
        return true;
    });
}

bool actionUIWinUIRichTextBlockSetSpacerWidth(ActionUIWinUIObject *block, int32_t paragraphIndex, int32_t inlineIndex,
                                              double width) {
    return guarded("rich text block set spacer width", [&]() {
        if (!(width >= 0 && width < 1000000.0)) {
            return fail("rich text block set spacer width", "the width must be 0 or more, and finite");
        }
        auto blocks = objectAs<muxc::RichTextBlock>(block, L"RichTextBlock").Blocks();
        if (paragraphIndex < 0 || static_cast<uint32_t>(paragraphIndex) >= blocks.Size()) {
            return fail("rich text block set spacer width", "no such paragraph");
        }
        docs::Paragraph paragraph = blocks.GetAt(static_cast<uint32_t>(paragraphIndex)).try_as<docs::Paragraph>();
        if (paragraph == nullptr || inlineIndex < 0 || static_cast<uint32_t>(inlineIndex) >= paragraph.Inlines().Size()) {
            return fail("rich text block set spacer width", "no such inline");
        }
        docs::InlineUIContainer container =
            paragraph.Inlines().GetAt(static_cast<uint32_t>(inlineIndex)).try_as<docs::InlineUIContainer>();
        mux::FrameworkElement space = container != nullptr ? container.Child().try_as<mux::FrameworkElement>() : nullptr;
        if (space == nullptr) {
            return fail("rich text block set spacer width", "the inline is not a spacer");
        }
        space.Width(width);
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
