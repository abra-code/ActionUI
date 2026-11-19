// Inputs.cpp - the controls that change a value: CheckBox, ToggleSwitch, TextBox; and operating
// them through UI Automation (toggle, set a value), as accessibility tools and tests do.

#include "ShimInternal.h"

#include <cstdlib>
#include <cstring>
#include <memory>

#include <winrt/Windows.System.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Provider.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>

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

bool actionUIWinUITextBoxSetText(ActionUIWinUIObject *textBox, const char *text) {
    return guarded("text box set text", [&]() {
        muxc::TextBox typed = objectAs<muxc::TextBox>(textBox, L"TextBox");
        winrt::hstring wanted = toHString(text);
        // Only when it differs: setting the text moves the caret.
        if (typed.Text() != wanted) {
            typed.Text(wanted);
        }
        return true;
    });
}

char *actionUIWinUITextBoxCopyText(ActionUIWinUIObject *textBox) {
    char *copy = nullptr;
    guarded("text box copy text", [&]() {
        std::string utf8 = winrt::to_string(objectAs<muxc::TextBox>(textBox, L"TextBox").Text());
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
        objectAs<muxc::TextBox>(textBox, L"TextBox").PlaceholderText(toHString(placeholder));
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
                               objectAs<muxc::TextBox>(textBox, L"TextBox")
                                   .TextChanged([holder](auto &&, auto &&) { holder->fire(); });
                           });
}

bool actionUIWinUITextBoxOnSubmit(ActionUIWinUIObject *textBox, ActionUIWinUICallback handler, void *context,
                                  ActionUIWinUICallback destroyContext) {
    return registerHandler("text box on submit", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) {
                               muxc::TextBox typed = objectAs<muxc::TextBox>(textBox, L"TextBox");
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
        if (toggler == nullptr) {
            return fail("automation toggle", "the element cannot be toggled");
        }
        toggler.Toggle();
        return true;
    });
}

bool actionUIWinUIAutomationSetValue(ActionUIWinUIObject *element, const char *value) {
    return guarded("automation set value", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        automation::Peers::AutomationPeer peer = peerFor(typed);
        wf::IInspectable pattern = peer.GetPattern(automation::Peers::PatternInterface::Value);
        automation::Provider::IValueProvider setter = pattern != nullptr ? pattern.try_as<automation::Provider::IValueProvider>() : nullptr;
        if (setter != nullptr) {
            setter.SetValue(toHString(value));
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
