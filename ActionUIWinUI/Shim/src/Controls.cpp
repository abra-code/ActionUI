// Controls.cpp - Button, and operating elements through UI Automation (what an accessibility tool,
// or a test, does).

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // ButtonBase: Click
#include <winrt/Microsoft.UI.Xaml.Automation.Provider.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>  // VisualTreeHelper

#include <vector>

namespace automation = winrt::Microsoft::UI::Xaml::Automation;
namespace media = winrt::Microsoft::UI::Xaml::Media;

using namespace actionui_winui;

namespace {

// The invoke pattern of `element`'s automation peer; null when it has none.
automation::Provider::IInvokeProvider invokerFor(mux::UIElement const &element) {
    automation::Peers::AutomationPeer peer = automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(element);
    if (peer == nullptr) {
        return nullptr;
    }
    wf::IInspectable pattern = peer.GetPattern(automation::Peers::PatternInterface::Invoke);
    return pattern != nullptr ? pattern.try_as<automation::Provider::IInvokeProvider>() : nullptr;
}

// The elements under `node` (not itself) that can be invoked, in the visual tree's order, depth first; the
// inside of one that can is not searched.
void collectInvokers(mux::DependencyObject const &node, std::vector<automation::Provider::IInvokeProvider> &found) {
    int32_t count = media::VisualTreeHelper::GetChildrenCount(node);
    for (int32_t index = 0; index < count; ++index) {
        mux::DependencyObject child = media::VisualTreeHelper::GetChild(node, index);
        if (mux::UIElement element = child.try_as<mux::UIElement>()) {
            if (automation::Provider::IInvokeProvider invoker = invokerFor(element)) {
                found.push_back(invoker);
                continue;
            }
        }
        collectInvokers(child, found);
    }
}

// The selection item pattern of `element`'s automation peer (an item of a list or a selector bar); null
// when it has none.
automation::Provider::ISelectionItemProvider selectionItemFor(mux::UIElement const &element) {
    automation::Peers::AutomationPeer peer = automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(element);
    if (peer == nullptr) {
        return nullptr;
    }
    wf::IInspectable pattern = peer.GetPattern(automation::Peers::PatternInterface::SelectionItem);
    return pattern != nullptr ? pattern.try_as<automation::Provider::ISelectionItemProvider>() : nullptr;
}

// The elements under `node` (not itself) that can be selected, in the visual tree's order, depth first;
// the inside of one that can is not searched.
void collectSelectionItems(mux::DependencyObject const &node, std::vector<automation::Provider::ISelectionItemProvider> &found) {
    int32_t count = media::VisualTreeHelper::GetChildrenCount(node);
    for (int32_t index = 0; index < count; ++index) {
        mux::DependencyObject child = media::VisualTreeHelper::GetChild(node, index);
        if (mux::UIElement element = child.try_as<mux::UIElement>()) {
            if (automation::Provider::ISelectionItemProvider item = selectionItemFor(element)) {
                found.push_back(item);
                continue;
            }
        }
        collectSelectionItems(child, found);
    }
}

} // namespace


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

bool actionUIWinUIAutomationInvokePart(ActionUIWinUIObject *element, int32_t index) {
    return guarded("automation invoke part", [&]() {
        std::vector<automation::Provider::IInvokeProvider> found;
        collectInvokers(objectAs<mux::UIElement>(element, L"UIElement"), found);
        if (index < 0 || static_cast<size_t>(index) >= found.size()) {
            return fail("automation invoke part", "no such part can be invoked");
        }
        found[static_cast<size_t>(index)].Invoke();
        return true;
    });
}

bool actionUIWinUIAutomationSelectPart(ActionUIWinUIObject *element, int32_t index) {
    return guarded("automation select part", [&]() {
        std::vector<automation::Provider::ISelectionItemProvider> found;
        collectSelectionItems(objectAs<mux::UIElement>(element, L"UIElement"), found);
        if (index < 0 || static_cast<size_t>(index) >= found.size()) {
            return fail("automation select part", "no such part can be selected");
        }
        found[static_cast<size_t>(index)].Select();
        return true;
    });
}

} // extern "C"
