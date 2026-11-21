// Decoration.cpp - what an element's box draws around and over it beyond padding, frame and background:
// a rounded box that clips what it holds to its rounded corners (the transform and the clip shape are in
// Effects.cpp).

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIRoundedBoxCreate(ActionUIWinUIObject *child) {
    return guardedObject("rounded box create", [&]() {
        mux::UIElement content = objectAs<mux::UIElement>(child, L"UIElement");
        muxc::Border box;
        // Neither the box nor its outline take room: the child fills it.
        box.BorderThickness(mux::Thickness{0, 0, 0, 0});
        box.Padding(mux::Thickness{0, 0, 0, 0});
        box.Child(content);
        return toObject(box);
    });
}

bool actionUIWinUIRoundedBoxSetCornerRadius(ActionUIWinUIObject *box, double radius) {
    return guarded("rounded box set corner radius", [&]() {
        muxc::Border border = objectAs<muxc::Border>(box, L"Border");
        if (!(radius >= 0)) {
            return fail("rounded box set corner radius", "the radius is not a number of pixels");
        }
        // Set only when it changed (as WinUI keeps it, a float), so an arrange does not redraw for nothing.
        mux::CornerRadius current = border.CornerRadius();
        float wanted = static_cast<float>(radius);
        if (static_cast<float>(current.TopLeft) != wanted || static_cast<float>(current.TopRight) != wanted ||
            static_cast<float>(current.BottomRight) != wanted || static_cast<float>(current.BottomLeft) != wanted) {
            border.CornerRadius(mux::CornerRadius{radius, radius, radius, radius});
        }
        return true;
    });
}

} // extern "C"
