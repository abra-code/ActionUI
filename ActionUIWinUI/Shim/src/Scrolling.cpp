// Scrolling.cpp - ScrollViewer, and placing an element within the slot its parent arranges it in
// (FrameworkElement's alignments).

#include "ShimInternal.h"

#include <cmath>

#include <winrt/Windows.Foundation.h>

using namespace actionui_winui;

namespace {

mux::HorizontalAlignment horizontalAlignment(int32_t value) {
    switch (value) {
    case ActionUIWinUIAlignStart: return mux::HorizontalAlignment::Left;
    case ActionUIWinUIAlignCenter: return mux::HorizontalAlignment::Center;
    case ActionUIWinUIAlignEnd: return mux::HorizontalAlignment::Right;
    default: return mux::HorizontalAlignment::Stretch;
    }
}

mux::VerticalAlignment verticalAlignment(int32_t value) {
    switch (value) {
    case ActionUIWinUIAlignStart: return mux::VerticalAlignment::Top;
    case ActionUIWinUIAlignCenter: return mux::VerticalAlignment::Center;
    case ActionUIWinUIAlignEnd: return mux::VerticalAlignment::Bottom;
    default: return mux::VerticalAlignment::Stretch;
    }
}

muxc::ScrollViewer scrollFrom(ActionUIWinUIObject *scroll) {
    return objectAs<muxc::ScrollViewer>(scroll, L"ScrollViewer");
}

} // namespace

extern "C" {

bool actionUIWinUIElementSetAlignment(ActionUIWinUIObject *element, ActionUIWinUIAlignment horizontal,
                                      ActionUIWinUIAlignment vertical) {
    return guarded("element set alignment", [&]() {
        mux::FrameworkElement typed = objectAs<mux::FrameworkElement>(element, L"FrameworkElement");
        mux::HorizontalAlignment wantedHorizontal = horizontalAlignment(horizontal);
        mux::VerticalAlignment wantedVertical = verticalAlignment(vertical);
        if (typed.HorizontalAlignment() != wantedHorizontal) {
            typed.HorizontalAlignment(wantedHorizontal);
        }
        if (typed.VerticalAlignment() != wantedVertical) {
            typed.VerticalAlignment(wantedVertical);
        }
        return true;
    });
}

ActionUIWinUIObject *actionUIWinUIScrollViewerCreate(void) {
    return guardedObject("scroll viewer create", []() {
        muxc::ScrollViewer scroll;
        // No zooming: a ScrollView scrolls only.
        scroll.ZoomMode(muxc::ZoomMode::Disabled);
        return toObject(scroll);
    });
}

bool actionUIWinUIScrollViewerSetAxes(ActionUIWinUIObject *scroll, bool horizontal, bool vertical, bool showsIndicators) {
    return guarded("scroll viewer set axes", [&]() {
        muxc::ScrollViewer typed = scrollFrom(scroll);
        // An axis that does not scroll is Disabled: the content is then measured with the viewer's
        // size in it, not an unbounded one.
        muxc::ScrollBarVisibility shown = showsIndicators ? muxc::ScrollBarVisibility::Auto : muxc::ScrollBarVisibility::Hidden;
        muxc::ScrollBarVisibility wantedHorizontal = horizontal ? shown : muxc::ScrollBarVisibility::Disabled;
        muxc::ScrollBarVisibility wantedVertical = vertical ? shown : muxc::ScrollBarVisibility::Disabled;
        if (typed.HorizontalScrollBarVisibility() != wantedHorizontal) {
            typed.HorizontalScrollBarVisibility(wantedHorizontal);
        }
        if (typed.VerticalScrollBarVisibility() != wantedVertical) {
            typed.VerticalScrollBarVisibility(wantedVertical);
        }
        muxc::ScrollMode horizontalMode = horizontal ? muxc::ScrollMode::Enabled : muxc::ScrollMode::Disabled;
        muxc::ScrollMode verticalMode = vertical ? muxc::ScrollMode::Enabled : muxc::ScrollMode::Disabled;
        if (typed.HorizontalScrollMode() != horizontalMode) {
            typed.HorizontalScrollMode(horizontalMode);
        }
        if (typed.VerticalScrollMode() != verticalMode) {
            typed.VerticalScrollMode(verticalMode);
        }
        return true;
    });
}

bool actionUIWinUIScrollViewerSetContent(ActionUIWinUIObject *scroll, ActionUIWinUIObject *element) {
    return guarded("scroll viewer set content", [&]() {
        muxc::ScrollViewer typed = scrollFrom(scroll);
        if (element == nullptr) {
            typed.Content(nullptr);
            return true;
        }
        mux::UIElement content = objectAs<mux::UIElement>(element, L"UIElement");
        if (typed.Content() != content) {
            typed.Content(content);
        }
        return true;
    });
}

bool actionUIWinUIScrollViewerScrollTo(ActionUIWinUIObject *scroll, double x, double y) {
    return guarded("scroll viewer scroll to", [&]() {
        if (!(std::isfinite(x) && std::isfinite(y))) {
            return fail("scroll viewer scroll to", "the offset is not finite");
        }
        // Without animation, so the next layout shows the new offset.
        bool changed = scrollFrom(scroll).ChangeView(winrt::box_value(x).as<wf::IReference<double>>(),
                                                     winrt::box_value(y).as<wf::IReference<double>>(), nullptr, true);
        if (!changed) {
            return fail("scroll viewer scroll to", "the ScrollViewer refused the offset");
        }
        return true;
    });
}

ActionUIWinUIScrollState actionUIWinUIScrollViewerState(ActionUIWinUIObject *scroll) {
    ActionUIWinUIScrollState state{};
    guarded("scroll viewer state", [&]() {
        muxc::ScrollViewer typed = scrollFrom(scroll);
        state.offsetX = typed.HorizontalOffset();
        state.offsetY = typed.VerticalOffset();
        state.viewportWidth = typed.ViewportWidth();
        state.viewportHeight = typed.ViewportHeight();
        state.extentWidth = typed.ExtentWidth();
        state.extentHeight = typed.ExtentHeight();
        return true;
    });
    return state;
}

} // extern "C"
