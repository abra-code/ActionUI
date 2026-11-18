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

} // extern "C"
