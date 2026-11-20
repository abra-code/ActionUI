// Text.cpp - TextBlock, WinUI's read-only text.

#include "ShimInternal.h"

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUITextBlockCreate(void) {
    return guardedObject("text block create", []() {
        muxc::TextBlock textBlock;
        return toObject(textBlock);
    });
}

bool actionUIWinUITextBlockSetText(ActionUIWinUIObject *textBlock, const char *text) {
    return guarded("text block set text", [&]() {
        objectAs<muxc::TextBlock>(textBlock, L"TextBlock").Text(toHString(text));
        return true;
    });
}

bool actionUIWinUITextBlockSetWraps(ActionUIWinUIObject *textBlock, bool wraps) {
    return guarded("text block set wraps", [&]() {
        // Wrap, not WrapWholeWords: a word that does not fit breaks too, as SwiftUI's Text does.
        objectAs<muxc::TextBlock>(textBlock, L"TextBlock")
            .TextWrapping(wraps ? mux::TextWrapping::Wrap : mux::TextWrapping::NoWrap);
        return true;
    });
}

bool actionUIWinUITextBlockSetTrimmed(ActionUIWinUIObject *textBlock, bool trimmed) {
    return guarded("text block set trimmed", [&]() {
        objectAs<muxc::TextBlock>(textBlock, L"TextBlock")
            .TextTrimming(trimmed ? mux::TextTrimming::CharacterEllipsis : mux::TextTrimming::None);
        return true;
    });
}

bool actionUIWinUITextBlockSetAlignment(ActionUIWinUIObject *textBlock, ActionUIWinUITextAlignment alignment) {
    return guarded("text block set alignment", [&]() {
        mux::TextAlignment wanted = alignment == ActionUIWinUITextCenter   ? mux::TextAlignment::Center
                                    : alignment == ActionUIWinUITextTrailing ? mux::TextAlignment::Right
                                                                             : mux::TextAlignment::Left;
        objectAs<muxc::TextBlock>(textBlock, L"TextBlock").TextAlignment(wanted);
        return true;
    });
}

} // extern "C"
