// Inputs.cpp - the controls that change a value: CheckBox, ToggleSwitch, TextBox, PasswordBox; and
// operating them through UI Automation (toggle, set a value), as accessibility tools and tests do.

#include "ShimInternal.h"

#include <cctype>
#include <cstdlib>
#include <cstring>
#include <memory>

#include <winrt/Windows.System.h>
#include <winrt/Microsoft.UI.Xaml.Automation.h>  // ExpandCollapseState
#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Provider.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>  // VisualTreeHelper
#include <winrt/Windows.UI.h>  // Color

namespace automation = winrt::Microsoft::UI::Xaml::Automation;

using namespace actionui_winui;

namespace {

// The UI Automation peer of `element`, or a recorded failure.
automation::Peers::AutomationPeer peerFor(mux::UIElement const &element) {
    automation::Peers::AutomationPeer peer = automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(element);
    if (peer == nullptr) {
        throw winrt::hresult_error(E_NOINTERFACE, L"the element has no automation peer");
    }
    return peer;
}

// The ColorPicker in the flyout of the first color button at or under `node`; null when there is none.
muxc::ColorPicker colorPickerInside(mux::DependencyObject const &node) {
    if (muxc::Button button = node.try_as<muxc::Button>()) {
        muxc::Flyout flyout = button.Flyout() != nullptr ? button.Flyout().try_as<muxc::Flyout>() : nullptr;
        if (muxc::ColorPicker picker = flyout != nullptr ? flyout.Content().try_as<muxc::ColorPicker>() : nullptr) {
            return picker;
        }
    }
    int32_t count = winrt::Microsoft::UI::Xaml::Media::VisualTreeHelper::GetChildrenCount(node);
    for (int32_t index = 0; index < count; ++index) {
        if (muxc::ColorPicker picker = colorPickerInside(winrt::Microsoft::UI::Xaml::Media::VisualTreeHelper::GetChild(node, index))) {
            return picker;
        }
    }
    return nullptr;
}

// "#RRGGBB" or "#RRGGBBAA" into `color`; false for anything else.
bool parseHexColor(const char *text, winrt::Windows::UI::Color &color) {
    if (text == nullptr || text[0] != '#') {
        return false;
    }
    size_t length = std::strlen(text + 1);
    if (length != 6 && length != 8) {
        return false;
    }
    uint8_t parts[4] = {0, 0, 0, 255};
    for (size_t part = 0; part < length / 2; ++part) {
        char pair[3] = {text[1 + part * 2], text[2 + part * 2], '\0'};
        // Two hex digits only: strtoul alone would take " 1", "+1" and "-1".
        if (!std::isxdigit(static_cast<unsigned char>(pair[0])) || !std::isxdigit(static_cast<unsigned char>(pair[1]))) {
            return false;
        }
        parts[part] = static_cast<uint8_t>(std::strtoul(pair, nullptr, 16));
    }
    color = winrt::Windows::UI::Color{parts[3], parts[0], parts[1], parts[2]};
    return true;
}

} // namespace

extern "C" {

// MARK: - CheckBox

ActionUIWinUIObject *actionUIWinUICheckBoxCreate(void) {
    return guardedObject("check box create", []() {
        muxc::CheckBox box;
        return toObject(box);
    });
}

bool actionUIWinUICheckBoxSetTitle(ActionUIWinUIObject *checkBox, const char *title) {
    return guarded("check box set title", [&]() {
        objectAs<muxc::CheckBox>(checkBox, L"CheckBox").Content(winrt::box_value(toHString(title)));
        return true;
    });
}

bool actionUIWinUICheckBoxSetChecked(ActionUIWinUIObject *checkBox, bool checked) {
    return guarded("check box set checked", [&]() {
        muxc::CheckBox typed = objectAs<muxc::CheckBox>(checkBox, L"CheckBox");
        auto current = typed.IsChecked();
        if (current == nullptr || current.Value() != checked) {
            typed.IsChecked(checked);
        }
        return true;
    });
}

bool actionUIWinUICheckBoxIsChecked(ActionUIWinUIObject *checkBox) {
    bool checked = false;
    guarded("check box is checked", [&]() {
        auto current = objectAs<muxc::CheckBox>(checkBox, L"CheckBox").IsChecked();
        checked = current != nullptr && current.Value();
        return true;
    });
    return checked;
}

bool actionUIWinUICheckBoxOnClick(ActionUIWinUIObject *checkBox, ActionUIWinUICallback handler, void *context,
                                  ActionUIWinUICallback destroyContext) {
    return registerHandler("check box on click", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::CheckBox>(checkBox, L"CheckBox").Click([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

// MARK: - ToggleSwitch

ActionUIWinUIObject *actionUIWinUIToggleSwitchCreate(void) {
    return guardedObject("toggle switch create", []() {
        muxc::ToggleSwitch toggle;
        return toObject(toggle);
    });
}

bool actionUIWinUIToggleSwitchSetTitle(ActionUIWinUIObject *toggleSwitch, const char *title) {
    return guarded("toggle switch set title", [&]() {
        muxc::ToggleSwitch typed = objectAs<muxc::ToggleSwitch>(toggleSwitch, L"ToggleSwitch");
        if (title == nullptr) {
            // No text, and no room kept for one (the style's minimum width is the text's).
            typed.OnContent(nullptr);
            typed.OffContent(nullptr);
            typed.MinWidth(0);
            return true;
        }
        typed.ClearValue(mux::FrameworkElement::MinWidthProperty());
        wf::IInspectable content = winrt::box_value(toHString(title));
        // The same text on and off, in place of WinUI's own "On" and "Off".
        typed.OnContent(content);
        typed.OffContent(content);
        return true;
    });
}

bool actionUIWinUIToggleSwitchSetOn(ActionUIWinUIObject *toggleSwitch, bool on) {
    return guarded("toggle switch set on", [&]() {
        muxc::ToggleSwitch typed = objectAs<muxc::ToggleSwitch>(toggleSwitch, L"ToggleSwitch");
        if (typed.IsOn() != on) {
            typed.IsOn(on);
        }
        return true;
    });
}

bool actionUIWinUIToggleSwitchIsOn(ActionUIWinUIObject *toggleSwitch) {
    bool on = false;
    guarded("toggle switch is on", [&]() {
        on = objectAs<muxc::ToggleSwitch>(toggleSwitch, L"ToggleSwitch").IsOn();
        return true;
    });
    return on;
}

bool actionUIWinUIToggleSwitchOnToggled(ActionUIWinUIObject *toggleSwitch, ActionUIWinUICallback handler, void *context,
                                        ActionUIWinUICallback destroyContext) {
    return registerHandler("toggle switch on toggled", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               objectAs<muxc::ToggleSwitch>(toggleSwitch, L"ToggleSwitch")
                                   .Toggled([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

// MARK: - TextBox

ActionUIWinUIObject *actionUIWinUITextBoxCreate(void) {
    return guardedObject("text box create", []() {
        muxc::TextBox box;
        return toObject(box);
    });
}

ActionUIWinUIObject *actionUIWinUIPasswordBoxCreate(void) {
    return guardedObject("password box create", []() {
        muxc::PasswordBox box;
        // No button to show the text, as macOS's SecureField has none.
        box.PasswordRevealMode(muxc::PasswordRevealMode::Hidden);
        return toObject(box);
    });
}

bool actionUIWinUITextBoxSetText(ActionUIWinUIObject *textBox, const char *text) {
    return guarded("text box set text", [&]() {
        winrt::hstring wanted = toHString(text);
        // Only when it differs: setting the text moves the caret.
        if (muxc::PasswordBox password = objectAs<wf::IInspectable>(textBox, L"IInspectable").try_as<muxc::PasswordBox>()) {
            if (password.Password() != wanted) {
                password.Password(wanted);
            }
            return true;
        }
        muxc::TextBox typed = objectAs<muxc::TextBox>(textBox, L"TextBox or PasswordBox");
        if (typed.Text() != wanted) {
            typed.Text(wanted);
        }
        return true;
    });
}

char *actionUIWinUITextBoxCopyText(ActionUIWinUIObject *textBox) {
    char *copy = nullptr;
    guarded("text box copy text", [&]() {
        wf::IInspectable object = objectAs<wf::IInspectable>(textBox, L"IInspectable");
        muxc::PasswordBox password = object.try_as<muxc::PasswordBox>();
        std::string utf8 = winrt::to_string(password != nullptr ? password.Password()
                                                                : objectAs<muxc::TextBox>(textBox, L"TextBox or PasswordBox").Text());
        copy = static_cast<char *>(malloc(utf8.size() + 1));
        if (copy == nullptr) {
            return fail("text box copy text", "out of memory");
        }
        memcpy(copy, utf8.c_str(), utf8.size() + 1);
        return true;
    });
    return copy;
}

void actionUIWinUIFreeString(char *string) {
    free(string);
}

bool actionUIWinUITextBoxSetPlaceholder(ActionUIWinUIObject *textBox, const char *placeholder) {
    return guarded("text box set placeholder", [&]() {
        if (muxc::PasswordBox password = objectAs<wf::IInspectable>(textBox, L"IInspectable").try_as<muxc::PasswordBox>()) {
            password.PlaceholderText(toHString(placeholder));
            return true;
        }
        objectAs<muxc::TextBox>(textBox, L"TextBox or PasswordBox").PlaceholderText(toHString(placeholder));
        return true;
    });
}

bool actionUIWinUITextBoxSetMultiline(ActionUIWinUIObject *textBox) {
    return guarded("text box set multiline", [&]() {
        muxc::TextBox typed = objectAs<muxc::TextBox>(textBox, L"TextBox");
        typed.AcceptsReturn(true);
        typed.TextWrapping(mux::TextWrapping::Wrap);
        muxc::ScrollViewer::SetVerticalScrollBarVisibility(typed, muxc::ScrollBarVisibility::Auto);
        return true;
    });
}

bool actionUIWinUITextBoxSetReadOnly(ActionUIWinUIObject *textBox, bool readOnly) {
    return guarded("text box set read only", [&]() {
        muxc::TextBox typed = objectAs<muxc::TextBox>(textBox, L"TextBox");
        if (typed.IsReadOnly() != readOnly) {
            typed.IsReadOnly(readOnly);
        }
        return true;
    });
}

bool actionUIWinUITextBoxOnTextChanged(ActionUIWinUIObject *textBox, ActionUIWinUICallback handler, void *context,
                                       ActionUIWinUICallback destroyContext) {
    return registerHandler("text box on text changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               if (muxc::PasswordBox password =
                                       objectAs<wf::IInspectable>(textBox, L"IInspectable").try_as<muxc::PasswordBox>()) {
                                   password.PasswordChanged([holder](auto &&, auto &&) { holder->fire(); });
                                   return;
                               }
                               objectAs<muxc::TextBox>(textBox, L"TextBox or PasswordBox")
                                   .TextChanged([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUITextBoxOnSubmit(ActionUIWinUIObject *textBox, ActionUIWinUICallback handler, void *context,
                                  ActionUIWinUICallback destroyContext) {
    return registerHandler("text box on submit", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               // A TextBox or a PasswordBox: both are Controls with these events.
                               muxc::Control typed = objectAs<muxc::Control>(textBox, L"TextBox or PasswordBox");
                               typed.KeyDown([holder](auto &&, mux::Input::KeyRoutedEventArgs const &args) {
                                   if (args.Key() == winrt::Windows::System::VirtualKey::Enter) {
                                       holder->fire();
                                   }
                               });
                               typed.LostFocus([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

// MARK: - Automation

bool actionUIWinUIAutomationToggle(ActionUIWinUIObject *element) {
    return guarded("automation toggle", [&]() {
        automation::Peers::AutomationPeer peer = peerFor(objectAs<mux::UIElement>(element, L"UIElement"));
        wf::IInspectable pattern = peer.GetPattern(automation::Peers::PatternInterface::Toggle);
        automation::Provider::IToggleProvider toggler = pattern != nullptr ? pattern.try_as<automation::Provider::IToggleProvider>() : nullptr;
        if (toggler != nullptr) {
            toggler.Toggle();
            return true;
        }
        // An expander: expanded if collapsed, collapsed if expanded.
        wf::IInspectable expandPattern = peer.GetPattern(automation::Peers::PatternInterface::ExpandCollapse);
        automation::Provider::IExpandCollapseProvider expander =
            expandPattern != nullptr ? expandPattern.try_as<automation::Provider::IExpandCollapseProvider>() : nullptr;
        if (expander == nullptr) {
            return fail("automation toggle", "the element cannot be toggled, expanded or collapsed");
        }
        if (expander.ExpandCollapseState() == automation::ExpandCollapseState::Collapsed) {
            expander.Expand();
        } else {
            expander.Collapse();
        }
        return true;
    });
}

bool actionUIWinUIAutomationSetValue(ActionUIWinUIObject *element, const char *value) {
    return guarded("automation set value", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        // A ColorPicker's view (its title and its color button): the button's picker takes the color, as a
        // pick in its flyout does.
        if (muxc::ColorPicker picker = colorPickerInside(typed)) {
            winrt::Windows::UI::Color color{};
            if (!parseHexColor(value, color)) {
                return fail("automation set value", "the value is not a color (#RRGGBB or #RRGGBBAA)");
            }
            picker.Color(color);
            return true;
        }
        automation::Peers::AutomationPeer peer = peerFor(typed);
        wf::IInspectable pattern = peer.GetPattern(automation::Peers::PatternInterface::Value);
        automation::Provider::IValueProvider setter = pattern != nullptr ? pattern.try_as<automation::Provider::IValueProvider>() : nullptr;
        if (setter != nullptr) {
            setter.SetValue(toHString(value));
            return true;
        }
        // A Slider's peer offers RangeValue instead: the value read as a number.
        wf::IInspectable rangePattern = peer.GetPattern(automation::Peers::PatternInterface::RangeValue);
        automation::Provider::IRangeValueProvider ranger =
            rangePattern != nullptr ? rangePattern.try_as<automation::Provider::IRangeValueProvider>() : nullptr;
        if (ranger != nullptr) {
            if (value == nullptr) {
                return fail("automation set value", "no number for a range value");
            }
            char *end = nullptr;
            double number = std::strtod(value, &end);
            if (end == value) {
                return fail("automation set value", "the value is not a number");
            }
            ranger.SetValue(number);
            return true;
        }
        // A PasswordBox whose peer offers no Value pattern (a password is not read out) is set as typing
        // replaces it, through Password, which raises PasswordChanged as typing does.
        if (muxc::PasswordBox password = typed.try_as<muxc::PasswordBox>()) {
            password.Password(toHString(value));
            return true;
        }
        // WinUI 2.7's TextBox peer offers no Value pattern (measured on a Windows runner): its text
        // is set as typing replaces it, through Text, which raises TextChanged as typing does.
        muxc::TextBox box = typed.try_as<muxc::TextBox>();
        if (box == nullptr) {
            return fail("automation set value", "the element takes no value");
        }
        box.Text(toHString(value));
        return true;
    });
}

} // extern "C"
