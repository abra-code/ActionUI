// Layout.cpp - a Panel whose measure and arrange passes are the caller's (C callbacks), and the
// element calls those passes use: measure, arrange, invalidate, the last placed frame, a clip.

#include "ShimInternal.h"

#include <cfloat>
#include <cmath>
#include <limits>

#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>  // RectangleGeometry

namespace actionui_winui {

namespace {

// A size WinUI accepts from MeasureOverride: finite and not negative (it throws otherwise). A
// double past the float range is capped: converted as is, it would be undefined (infinity on MSVC).
float layoutLength(double value) {
    if (!(std::isfinite(value) && value > 0)) {
        return 0.0f;
    }
    return value <= FLT_MAX ? static_cast<float>(value) : FLT_MAX;
}

// A size offered to Measure: infinity, or a double past the float range, is "as much as wanted";
// NaN or a negative size, which WinUI would throw on, is 0.
float offeredLength(double value) {
    if (std::isnan(value) || value < 0) {
        return 0.0f;
    }
    return value <= FLT_MAX ? static_cast<float>(value) : std::numeric_limits<float>::infinity();
}

struct CallbackPanel : muxc::PanelT<CallbackPanel> {
    CallbackPanel(ActionUIWinUIMeasureCallback measure, ActionUIWinUIArrangeCallback arrange, void *context,
                  ActionUIWinUICallback destroyContext)
        : m_measure(measure), m_arrange(arrange), m_context(context), m_destroyContext(destroyContext),
          m_queue(dispatching::DispatcherQueue::GetForCurrentThread()) {}

    // On the thread that let go of the last reference. The context belongs to the UI thread (its
    // Swift side is main-actor isolated): from any other thread, destroyContext is sent there
    // (callOnUIThread).
    ~CallbackPanel() {
        callOnUIThread(m_queue, m_destroyContext, m_context);
    }

    wf::Size MeasureOverride(wf::Size available) {
        ActionUIWinUISize size{0, 0};
        if (m_measure != nullptr && m_self != nullptr) {
            size = m_measure(m_context, m_self, ActionUIWinUISize{available.Width, available.Height});
        }
        return wf::Size{layoutLength(size.width), layoutLength(size.height)};
    }

    wf::Size ArrangeOverride(wf::Size finalSize) {
        if (m_arrange != nullptr && m_self != nullptr) {
            m_arrange(m_context, m_self, ActionUIWinUISize{finalSize.Width, finalSize.Height});
        }
        return finalSize;
    }

    // The panel as the callbacks see it: one of its own interface pointers, not a reference (the
    // panel cannot hold a reference to itself). Valid while the panel lives.
    ActionUIWinUIObject *m_self = nullptr;

private:
    ActionUIWinUIMeasureCallback m_measure;
    ActionUIWinUIArrangeCallback m_arrange;
    void *m_context;
    ActionUIWinUICallback m_destroyContext;
    dispatching::DispatcherQueue m_queue;
};

muxc::Panel panelFrom(ActionUIWinUIObject *panel) {
    return objectAs<muxc::Panel>(panel, L"Panel");
}

mux::UIElement elementFrom(ActionUIWinUIObject *element) {
    return objectAs<mux::UIElement>(element, L"UIElement");
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIPanelCreate(ActionUIWinUIMeasureCallback measure, ActionUIWinUIArrangeCallback arrange,
                                              void *context, ActionUIWinUICallback destroyContext) {
    bool constructed = false;
    ActionUIWinUIObject *result = guardedObject("panel create", [&]() {
        // make_self keeps the implementation pointer: get_self cannot get back to it from the
        // composed Panel base.
        winrt::com_ptr<CallbackPanel> implementation =
            winrt::make_self<CallbackPanel>(measure, arrange, context, destroyContext);
        constructed = true;
        muxc::Panel panel = implementation.as<muxc::Panel>();
        implementation->m_self = static_cast<ActionUIWinUIObject *>(winrt::get_abi(panel));
        return toObject(panel);
    });
    // Once constructed, the panel's destructor calls destroyContext, also on a failure after it.
    if (result == nullptr && !constructed && destroyContext != nullptr) {
        destroyContext(context);
    }
    return result;
}

int32_t actionUIWinUIPanelChildCount(ActionUIWinUIObject *panel) {
    int32_t count = -1;
    guarded("panel child count", [&]() {
        count = static_cast<int32_t>(panelFrom(panel).Children().Size());
        return true;
    });
    return count;
}

bool actionUIWinUIPanelInsertChild(ActionUIWinUIObject *panel, int32_t index, ActionUIWinUIObject *child) {
    return guarded("panel insert child", [&]() {
        auto children = panelFrom(panel).Children();
        if (index < 0 || static_cast<uint32_t>(index) > children.Size()) {
            return fail("panel insert child", "the index is out of range");
        }
        children.InsertAt(static_cast<uint32_t>(index), elementFrom(child));
        return true;
    });
}

bool actionUIWinUIPanelRemoveChild(ActionUIWinUIObject *panel, int32_t index) {
    return guarded("panel remove child", [&]() {
        auto children = panelFrom(panel).Children();
        if (index < 0 || static_cast<uint32_t>(index) >= children.Size()) {
            return fail("panel remove child", "the index is out of range");
        }
        children.RemoveAt(static_cast<uint32_t>(index));
        return true;
    });
}

ActionUIWinUISize actionUIWinUIElementMeasure(ActionUIWinUIObject *element, ActionUIWinUISize available) {
    ActionUIWinUISize desired{0, 0};
    guarded("element measure", [&]() {
        mux::UIElement typed = elementFrom(element);
        typed.Measure(wf::Size{offeredLength(available.width), offeredLength(available.height)});
        wf::Size size = typed.DesiredSize();
        desired = ActionUIWinUISize{size.Width, size.Height};
        return true;
    });
    return desired;
}

bool actionUIWinUIElementArrange(ActionUIWinUIObject *element, ActionUIWinUIRect frame) {
    return guarded("element arrange", [&]() {
        // Also false for NaN and infinity.
        if (!(std::fabs(frame.x) <= FLT_MAX && std::fabs(frame.y) <= FLT_MAX)) {
            return fail("element arrange", "the position is not finite (or past the float range)");
        }
        elementFrom(element).Arrange(wf::Rect{static_cast<float>(frame.x), static_cast<float>(frame.y),
                                              layoutLength(frame.width), layoutLength(frame.height)});
        return true;
    });
}

bool actionUIWinUIElementInvalidateMeasure(ActionUIWinUIObject *element) {
    return guarded("element invalidate measure", [&]() {
        elementFrom(element).InvalidateMeasure();
        return true;
    });
}

ActionUIWinUIRect actionUIWinUIElementLayoutFrame(ActionUIWinUIObject *element) {
    ActionUIWinUIRect frame{0, 0, 0, 0};
    guarded("element layout frame", [&]() {
        mux::UIElement typed = elementFrom(element);
        winrt::Windows::Foundation::Numerics::float3 offset = typed.ActualOffset();
        winrt::Windows::Foundation::Numerics::float2 size = typed.ActualSize();
        frame = ActionUIWinUIRect{offset.x, offset.y, size.x, size.y};
        return true;
    });
    return frame;
}

bool actionUIWinUIElementSetClipSize(ActionUIWinUIObject *element, double width, double height) {
    return guarded("element set clip size", [&]() {
        mux::UIElement typed = elementFrom(element);
        if (!(std::isfinite(width) && width >= 0 && std::isfinite(height) && height >= 0)) {
            typed.Clip(nullptr);
            return true;
        }
        mux::Media::RectangleGeometry clip;
        clip.Rect(wf::Rect{0, 0, layoutLength(width), layoutLength(height)});
        typed.Clip(clip);
        return true;
    });
}

} // extern "C"
