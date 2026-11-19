// Controls.cpp - Button, and operating elements through UI Automation (what an accessibility tool,
// or a test, does).

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // ButtonBase: Click
#include <winrt/Microsoft.UI.Xaml.Automation.Provider.h>

namespace automation = winrt::Microsoft::UI::Xaml::Automation;

using namespace actionui_winui;


extern "C" {

ActionUIWinUIObject *actionUIWinUIButtonCreate(void) {
    return guardedObject("button create", []() {
        muxc::Button button;
        return toObject(button);
    });
}

bool actionUIWinUIButtonSetTitle(ActionUIWinUIObject *button, const char *title) {
    return guarded("button set title", [&]() {
        objectAs<muxc::Button>(button, L"Button").Content(winrt::box_value(toHString(title)));
        return true;
    });
}

bool actionUIWinUIButtonSetContent(ActionUIWinUIObject *button, ActionUIWinUIObject *content) {
    return guarded("button set content", [&]() {
        muxc::Button typed = objectAs<muxc::Button>(button, L"Button");
        if (content == nullptr) {
            typed.Content(nullptr);
        } else {
            typed.Content(objectAs<mux::UIElement>(content, L"UIElement"));
        }
        return true;
    });
}

bool actionUIWinUIButtonOnClick(ActionUIWinUIObject *button, ActionUIWinUICallback handler, void *context,
                                ActionUIWinUICallback destroyContext) {
    return registerHandler("button on click", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::Button>(button, L"Button").Click([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUIAutomationInvoke(ActionUIWinUIObject *element) {
    return guarded("automation invoke", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        automation::Peers::AutomationPeer peer = automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(typed);
        if (peer == nullptr) {
            return fail("automation invoke", "the element has no automation peer");
        }
        wf::IInspectable pattern = peer.GetPattern(automation::Peers::PatternInterface::Invoke);
        automation::Provider::IInvokeProvider invoker = pattern != nullptr ? pattern.try_as<automation::Provider::IInvokeProvider>() : nullptr;
        if (invoker == nullptr) {
            return fail("automation invoke", "the element cannot be invoked");
        }
        invoker.Invoke();
        return true;
    });
}

} // extern "C"
