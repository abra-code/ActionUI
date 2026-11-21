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

#include <cmath>
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

// The element named `name` under `node` (not itself), depth first; null when there is none (a
// template not yet applied has no elements).
mux::FrameworkElement namedDescendant(mux::DependencyObject const &node, wchar_t const *name) {
    int32_t count = media::VisualTreeHelper::GetChildrenCount(node);
    for (int32_t index = 0; index < count; ++index) {
        mux::DependencyObject child = media::VisualTreeHelper::GetChild(node, index);
        if (mux::FrameworkElement element = child.try_as<mux::FrameworkElement>(); element != nullptr && element.Name() == name) {
            return element;
        }
        if (mux::FrameworkElement found = namedDescendant(child, name)) {
            return found;
        }
    }
    return nullptr;
}

// The swatch's outline: the theme's control stroke, else a light gray.
media::Brush swatchStroke() {
    try {
        wf::IInspectable found = mux::Application::Current().Resources().Lookup(winrt::box_value(L"ControlStrokeColorDefaultBrush"));
        if (media::Brush brush = found.try_as<media::Brush>()) {
            return brush;
        }
    } catch (winrt::hresult_error const &) {
    }
    return media::SolidColorBrush(winrt::Windows::UI::Color{0x40, 0, 0, 0});
}

// A color button's picker, in its flyout.
muxc::ColorPicker pickerOf(muxc::Button const &button) {
    muxc::Flyout flyout = button.Flyout().try_as<muxc::Flyout>();
    muxc::ColorPicker picker = flyout != nullptr ? flyout.Content().try_as<muxc::ColorPicker>() : nullptr;
    if (picker == nullptr) {
        throw winrt::hresult_invalid_argument(L"not a color button");
    }
    return picker;
}

uint8_t colorChannel(double value) {
    double clamped = std::isfinite(value) ? (value < 0 ? 0.0 : (value > 1 ? 1.0 : value)) : 0.0;
    return static_cast<uint8_t>(clamped * 255.0 + 0.5);
}

} // namespace


extern "C" {

ActionUIWinUIObject *actionUIWinUIColorButtonCreate(void) {
    return guardedObject("color button create", [&]() {
        muxc::Button button;
        // A swatch 32 x 16 with the button's corners, the button a little tighter than a text button.
        button.Padding(mux::Thickness{6, 5, 6, 5});
        muxc::Border swatch;
        swatch.Width(32);
        swatch.Height(16);
        swatch.CornerRadius(mux::CornerRadius{2, 2, 2, 2});
        swatch.BorderThickness(mux::Thickness{1, 1, 1, 1});
        swatch.BorderBrush(swatchStroke());
        media::SolidColorBrush fill(winrt::Windows::UI::Color{0, 0, 0, 0});
        swatch.Background(fill);
        button.Content(swatch);
        automation::AutomationProperties::SetName(button, L"Color");
        muxc::ColorPicker picker;
        picker.IsAlphaEnabled(true);
        picker.Color(winrt::Windows::UI::Color{0, 0, 0, 0});
        // The swatch follows the picker, whoever changed it.
        picker.ColorChanged([fill](auto &&, muxc::ColorChangedEventArgs const &args) { fill.Color(args.NewColor()); });
        muxc::Flyout flyout;
        flyout.Content(picker);
        button.Flyout(flyout);
        return toObject(button);
    });
}

bool actionUIWinUIColorButtonSetColor(ActionUIWinUIObject *button, ActionUIWinUIColor color) {
    return guarded("color button set color", [&]() {
        muxc::ColorPicker picker = pickerOf(objectAs<muxc::Button>(button, L"Button"));
        winrt::Windows::UI::Color wanted{colorChannel(color.alpha), colorChannel(color.red), colorChannel(color.green),
                                         colorChannel(color.blue)};
        if (picker.Color() != wanted) {
            picker.Color(wanted);
        }
        return true;
    });
}

bool actionUIWinUIColorButtonGetColor(ActionUIWinUIObject *button, ActionUIWinUIColor *color) {
    return guarded("color button get color", [&]() {
        if (color == nullptr) {
            return fail("color button get color", "no place for the color");
        }
        winrt::Windows::UI::Color shown = pickerOf(objectAs<muxc::Button>(button, L"Button")).Color();
        *color = ActionUIWinUIColor{shown.R / 255.0, shown.G / 255.0, shown.B / 255.0, shown.A / 255.0};
        return true;
    });
}

bool actionUIWinUIColorButtonOnColorChanged(ActionUIWinUIObject *button, ActionUIWinUICallback handler, void *context,
                                            ActionUIWinUICallback destroyContext) {
    return registerHandler("color button on color changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               pickerOf(objectAs<muxc::Button>(button, L"Button"))
                                   .ColorChanged([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

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

bool actionUIWinUIControlSetBox(ActionUIWinUIObject *control, double minHeight, double left, double top,
                                double right, double bottom) {
    return guarded("control set box", [&]() {
        muxc::Control typed = objectAs<muxc::Control>(control, L"Control");
        bool clear = !(minHeight >= 0);
        if (clear) {
            typed.ClearValue(mux::FrameworkElement::MinHeightProperty());
            typed.ClearValue(muxc::Control::PaddingProperty());
        } else {
            typed.MinHeight(minHeight);
            typed.Padding(mux::Thickness{left, top, right, bottom});
        }
        // A ComboBox's own style sets no minimum height: its 32 pixels are its template's dropdown glyph,
        // whose MinHeight (ComboBoxMinHeight) wins over its Height of 12, so a smaller box needs the glyph
        // smaller too. The key in the control's resources reaches a template applied later (and a theme
        // change); an applied template's glyph is set directly.
        if (muxc::ComboBox combo = typed.try_as<muxc::ComboBox>(); combo != nullptr) {
            mux::ResourceDictionary resources = combo.Resources();
            wf::IInspectable key = winrt::box_value(L"ComboBoxMinHeight");
            if (resources.HasKey(key)) {
                resources.Remove(key);
            }
            double glyphMinHeight = minHeight;
            if (clear) {
                glyphMinHeight = 32;
                try {
                    if (auto found = mux::Application::Current().Resources().Lookup(key).try_as<double>()) {
                        glyphMinHeight = *found;
                    }
                } catch (winrt::hresult_error const &) {
                }
            } else {
                resources.Insert(key, winrt::box_value(minHeight));
            }
            if (mux::FrameworkElement glyph = namedDescendant(combo, L"DropDownGlyph")) {
                glyph.MinHeight(glyphMinHeight);
            }
        }
        return true;
    });
}

bool actionUIWinUIButtonSetStyle(ActionUIWinUIObject *button, ActionUIWinUIButtonStyle style) {
    return guarded("button set style", [&]() {
        muxc::Button typed = objectAs<muxc::Button>(button, L"Button");
        // The resources a plain button replaces (WinUI's lightweight styling keys of its template).
        static const wchar_t *const plainKeys[] = {
            L"ButtonBackgroundPointerOver", L"ButtonBackgroundPressed",
            L"ButtonBorderBrushPointerOver", L"ButtonBorderBrushPressed",
        };
        // The resources a borderless or plain button replaces: the template's Disabled state fills the
        // button (ControlFillColorDisabledBrush) and draws its border, where these draw none.
        static const wchar_t *const disabledKeys[] = {
            L"ButtonBackgroundDisabled", L"ButtonBorderBrushDisabled",
        };
        // Back to the standard button.
        typed.ClearValue(mux::FrameworkElement::StyleProperty());
        typed.ClearValue(muxc::Control::BackgroundProperty());
        typed.ClearValue(muxc::Control::BorderBrushProperty());
        typed.ClearValue(muxc::Control::PaddingProperty());
        typed.ClearValue(mux::FrameworkElement::MinWidthProperty());
        typed.ClearValue(mux::FrameworkElement::MinHeightProperty());
        // Plain's no-border width, only that one: a ControlGroup's joined buttons set their own.
        mux::Thickness border = typed.BorderThickness();
        if (border.Left == 0 && border.Top == 0 && border.Right == 0 && border.Bottom == 0) {
            typed.ClearValue(muxc::Control::BorderThicknessProperty());
        }
        mux::ResourceDictionary resources = typed.Resources();
        for (const wchar_t *key : plainKeys) {
            wf::IInspectable boxed = winrt::box_value(key);
            if (resources.HasKey(boxed)) {
                resources.Remove(boxed);
            }
        }
        for (const wchar_t *key : disabledKeys) {
            wf::IInspectable boxed = winrt::box_value(key);
            if (resources.HasKey(boxed)) {
                resources.Remove(boxed);
            }
        }
        switch (style) {
        case ActionUIWinUIButtonStyleStandard:
            break;
        case ActionUIWinUIButtonStyleAccent: {
            wf::IInspectable found{nullptr};
            try {
                found = mux::Application::Current().Resources().Lookup(winrt::box_value(L"AccentButtonStyle"));
            } catch (winrt::hresult_error const &) {
            }
            mux::Style accent = found != nullptr ? found.try_as<mux::Style>() : nullptr;
            if (accent == nullptr) {
                return fail("button set style", "the theme has no AccentButtonStyle");
            }
            typed.Style(accent);
            break;
        }
        case ActionUIWinUIButtonStyleBorderless:
        case ActionUIWinUIButtonStylePlain: {
            media::SolidColorBrush clear(winrt::Windows::UI::Color{0, 0, 0, 0});
            typed.Background(clear);
            typed.BorderBrush(clear);
            for (const wchar_t *key : disabledKeys) {
                resources.Insert(winrt::box_value(key), clear);
            }
            if (style == ActionUIWinUIButtonStylePlain) {
                typed.Padding(mux::Thickness{0, 0, 0, 0});
                typed.BorderThickness(mux::Thickness{0, 0, 0, 0});
                typed.MinWidth(0);
                typed.MinHeight(0);
                for (const wchar_t *key : plainKeys) {
                    resources.Insert(winrt::box_value(key), clear);
                }
            }
            break;
        }
        default:
            return fail("button set style", "unknown button style");
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

ActionUIWinUIObject *actionUIWinUIPaneToggleButtonCreate(void) {
    return guardedObject("pane toggle button create", []() {
        muxc::Button button;
        wf::IInspectable found{nullptr};
        try {
            found = mux::Application::Current().Resources().Lookup(winrt::box_value(L"PaneToggleButtonStyle"));
        } catch (winrt::hresult_error const &) {
            // Not in this theme: drawn by hand below.
        }
        mux::Style style = found != nullptr ? found.try_as<mux::Style>() : nullptr;
        if (style != nullptr) {
            button.Style(style);
        } else {
            // The GlobalNavigationButton glyph (three lines) of the system's symbol font, as the style
            // draws it.
            muxc::FontIcon glyph;
            glyph.Glyph(L"\uE700");
            glyph.FontSize(16);
            button.Content(glyph);
            button.Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
            button.BorderThickness(mux::Thickness{0, 0, 0, 0});
            button.Padding(mux::Thickness{0, 0, 0, 0});
            button.Width(40);
            button.Height(36);
        }
        automation::AutomationProperties::SetName(button, L"Show or hide the sidebar");
        muxc::ToolTipService::SetToolTip(button, winrt::box_value(L"Show or hide the sidebar"));
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

bool actionUIWinUIHyperlinkOnClick(ActionUIWinUIObject *link, ActionUIWinUICallback handler, void *context,
                                   ActionUIWinUICallback destroyContext) {
    return registerHandler("hyperlink on click", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::HyperlinkButton>(link, L"HyperlinkButton").Click([holder](auto &&, auto &&) {
                                   holder->fire();
                               });
                           });
}

ActionUIWinUIObject *actionUIWinUIExpanderCreate(ActionUIWinUIObject *content) {
    return guardedObject("expander create", [&]() {
        muxc::Expander expander;
        expander.HorizontalAlignment(mux::HorizontalAlignment::Stretch);
        expander.HorizontalContentAlignment(mux::HorizontalAlignment::Stretch);
        expander.Content(objectAs<mux::UIElement>(content, L"UIElement"));
        return toObject(expander);
    });
}

bool actionUIWinUIExpanderSetTitle(ActionUIWinUIObject *expander, const char *title) {
    return guarded("expander set title", [&]() {
        muxc::Expander typed = objectAs<muxc::Expander>(expander, L"Expander");
        winrt::hstring text = toHString(title);
        typed.Header(winrt::box_value(text));
        // The Expander's peer takes no name from its header: accessibility tools read it by the title.
        automation::AutomationProperties::SetName(typed, text);
        return true;
    });
}

bool actionUIWinUIExpanderSetExpanded(ActionUIWinUIObject *expander, bool expanded) {
    return guarded("expander set expanded", [&]() {
        muxc::Expander typed = objectAs<muxc::Expander>(expander, L"Expander");
        if (typed.IsExpanded() != expanded) {
            typed.IsExpanded(expanded);
        }
        return true;
    });
}

bool actionUIWinUIExpanderIsExpanded(ActionUIWinUIObject *expander) {
    bool expanded = false;
    guarded("expander is expanded", [&]() {
        expanded = objectAs<muxc::Expander>(expander, L"Expander").IsExpanded();
        return true;
    });
    return expanded;
}

bool actionUIWinUIExpanderOnExpandedChanged(ActionUIWinUIObject *expander, ActionUIWinUICallback handler, void *context,
                                            ActionUIWinUICallback destroyContext) {
    return registerHandler("expander on expanded changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               muxc::Expander typed = objectAs<muxc::Expander>(expander, L"Expander");
                               typed.Expanding([holder](auto &&, auto &&) { holder->fire(); });
                               typed.Collapsed([holder](auto &&, auto &&) { holder->fire(); });
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
