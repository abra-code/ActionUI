// Controls.cpp - Button and the back button, and operating elements through UI Automation (what an
// accessibility tool, or a test, does).

#include "ShimInternal.h"

#include <winrt/Windows.UI.h>  // Color
#include <winrt/Microsoft.UI.Xaml.Automation.h>  // AutomationProperties
#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // ButtonBase: Click
#include <winrt/Microsoft.UI.Xaml.Automation.Provider.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>  // Tapped, KeyUp
#include <winrt/Microsoft.UI.Xaml.Media.h>  // VisualTreeHelper
#include <winrt/Windows.System.h>          // VirtualKey

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

// When `element` is a selection container (its peer has the Selection pattern: a ListView), adds its
// items' selection item patterns, in order, from its peer's children, and returns true when it added
// any. A ListView's items are found only this way: the peer of an item's container (ListViewItem) has
// no SelectionItem pattern, the item's peer among the list's children has.
bool collectContainerSelectionItems(mux::UIElement const &element,
                                    std::vector<automation::Provider::ISelectionItemProvider> &found) {
    automation::Peers::AutomationPeer peer = automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(element);
    if (peer == nullptr || peer.GetPattern(automation::Peers::PatternInterface::Selection) == nullptr) {
        return false;
    }
    wf::Collections::IVector<automation::Peers::AutomationPeer> children = peer.GetChildren();
    if (children == nullptr) {
        return false;
    }
    size_t before = found.size();
    for (automation::Peers::AutomationPeer const &child : children) {
        wf::IInspectable pattern = child.GetPattern(automation::Peers::PatternInterface::SelectionItem);
        if (automation::Provider::ISelectionItemProvider item =
                pattern != nullptr ? pattern.try_as<automation::Provider::ISelectionItemProvider>() : nullptr) {
            found.push_back(item);
        }
    }
    return found.size() > before;
}

// The elements under `node` (not itself) that can be selected, in the visual tree's order, depth first
// (a selection container's items in its own order); the inside of one that can is not searched.
void collectSelectionItems(mux::DependencyObject const &node, std::vector<automation::Provider::ISelectionItemProvider> &found) {
    int32_t count = media::VisualTreeHelper::GetChildrenCount(node);
    for (int32_t index = 0; index < count; ++index) {
        mux::DependencyObject child = media::VisualTreeHelper::GetChild(node, index);
        if (mux::UIElement element = child.try_as<mux::UIElement>()) {
            if (automation::Provider::ISelectionItemProvider item = selectionItemFor(element)) {
                found.push_back(item);
                continue;
            }
            if (collectContainerSelectionItems(element, found)) {
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

ActionUIWinUIObject *actionUIWinUIBackButtonCreate(void) {
    return guardedObject("back button create", []() {
        muxc::Button button;
        wf::IInspectable found{nullptr};
        try {
            found = mux::Application::Current().Resources().Lookup(winrt::box_value(L"NavigationBackButtonNormalStyle"));
        } catch (winrt::hresult_error const &) {
            // Not in this theme: drawn by hand below.
        }
        mux::Style style = found != nullptr ? found.try_as<mux::Style>() : nullptr;
        if (style != nullptr) {
            button.Style(style);
        } else {
            // The Back glyph of the system's symbol font (Segoe Fluent Icons), as the style draws it; the
            // button's pointer-over and pressed fills still come from its template.
            muxc::FontIcon glyph;
            glyph.Glyph(L"\uE72B");
            glyph.FontSize(16);
            button.Content(glyph);
            button.Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
            button.BorderThickness(mux::Thickness{0, 0, 0, 0});
            button.Padding(mux::Thickness{0, 0, 0, 0});
            button.Width(40);
            button.Height(36);
        }
        automation::AutomationProperties::SetName(button, L"Back");
        muxc::ToolTipService::SetToolTip(button, winrt::box_value(L"Back"));
        return toObject(button);
    });
}

ActionUIWinUIObject *actionUIWinUIOverflowButtonCreate(ActionUIWinUIObject *content) {
    return guardedObject("overflow button create", [&]() {
        muxc::Button button;
        muxc::FontIcon glyph;
        glyph.Glyph(L"\uE712");  // More
        glyph.FontSize(16);
        button.Content(glyph);
        button.Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        button.BorderThickness(mux::Thickness{0, 0, 0, 0});
        automation::AutomationProperties::SetName(button, L"More options");
        muxc::ToolTipService::SetToolTip(button, winrt::box_value(L"More options"));
        muxc::Flyout flyout;
        mux::UIElement panel = objectAs<mux::UIElement>(content, L"UIElement");
        flyout.Content(panel);
        // Chosen an item, the flyout closes, as a menu does: a tap, or Enter or Space, in it (also when
        // the item handled the event itself, as a Button does).
        winrt::weak_ref<muxc::Flyout> weakFlyout = flyout;
        panel.AddHandler(mux::UIElement::TappedEvent(),
                         winrt::box_value(mux::Input::TappedEventHandler([weakFlyout](auto &&, auto &&) {
                             if (muxc::Flyout shown = weakFlyout.get()) {
                                 shown.Hide();
                             }
                         })),
                         true);
        panel.AddHandler(mux::UIElement::KeyUpEvent(),
                         winrt::box_value(mux::Input::KeyEventHandler([weakFlyout](wf::IInspectable const &,
                                                                                  mux::Input::KeyRoutedEventArgs const &args) {
                             winrt::Windows::System::VirtualKey key = args.Key();
                             if (key != winrt::Windows::System::VirtualKey::Enter && key != winrt::Windows::System::VirtualKey::Space) {
                                 return;
                             }
                             if (muxc::Flyout shown = weakFlyout.get()) {
                                 shown.Hide();
                             }
                         })),
                         true);
        button.Flyout(flyout);
        return toObject(button);
    });
}

ActionUIWinUIObject *actionUIWinUIHyperlinkCreate(void) {
    return guardedObject("hyperlink create", []() {
        muxc::HyperlinkButton link;
        // The default style also has a transparent border of 1 (HyperlinkButtonBorderThemeThickness), which
        // would set the text 1 in from the text around it.
        link.Padding(mux::Thickness{0, 0, 0, 0});
        link.BorderThickness(mux::Thickness{0, 0, 0, 0});
        link.MinWidth(0);
        link.MinHeight(0);
        return toObject(link);
    });
}

bool actionUIWinUIHyperlinkSetTitle(ActionUIWinUIObject *link, const char *title) {
    return guarded("hyperlink set title", [&]() {
        objectAs<muxc::HyperlinkButton>(link, L"HyperlinkButton").Content(winrt::box_value(toHString(title)));
        return true;
    });
}

bool actionUIWinUIHyperlinkSetURL(ActionUIWinUIObject *link, const char *url) {
    return guarded("hyperlink set url", [&]() {
        muxc::HyperlinkButton typed = objectAs<muxc::HyperlinkButton>(link, L"HyperlinkButton");
        typed.NavigateUri(url != nullptr ? wf::Uri(toHString(url)) : nullptr);
        return true;
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
