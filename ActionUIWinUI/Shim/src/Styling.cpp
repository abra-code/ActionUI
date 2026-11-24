// Styling.cpp - brushes (backgrounds and foregrounds, from a color or the theme) and fonts, on the
// elements that have them: panels, controls, text blocks; and an element's state: opacity, whether the
// pointer reaches it, whether a control is enabled, whether accessibility tools skip it.

#include "ShimInternal.h"

#include <cmath>
#include <cstdlib>  // malloc
#include <cstring>
#include <string>

#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Xaml.Automation.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>  // ToolTipService
#include <winrt/Microsoft.UI.Xaml.Input.h>     // KeyboardAccelerator
#include <winrt/Windows.System.h>              // VirtualKey
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

namespace media = winrt::Microsoft::UI::Xaml::Media;

using namespace actionui_winui;

namespace {

uint8_t channel(double value) {
    double clamped = std::isfinite(value) ? (value < 0 ? 0.0 : (value > 1 ? 1.0 : value)) : 0.0;
    return static_cast<uint8_t>(clamped * 255.0 + 0.5);
}

} // namespace

// The brush for `color`, or for the theme resource `themeBrush`; nullptr for neither (the
// element's own default). Throws when the theme has no such brush. Shared (ShimInternal.h).
media::Brush actionui_winui::brushFor(const ActionUIWinUIColor *color, const char *themeBrush) {
    if (color != nullptr) {
        return media::SolidColorBrush(winrt::Windows::UI::Color{channel(color->alpha), channel(color->red),
                                                               channel(color->green), channel(color->blue)});
    }
    if (themeBrush == nullptr || themeBrush[0] == '\0') {
        return nullptr;
    }
    winrt::hstring key = toHString(themeBrush);
    wf::IInspectable found{nullptr};
    try {
        found = mux::Application::Current().Resources().Lookup(winrt::box_value(key));
    } catch (winrt::hresult_error const &) {
        throw winrt::hresult_invalid_argument(L"the theme has no resource " + key);
    }
    media::Brush brush = found != nullptr ? found.try_as<media::Brush>() : nullptr;
    if (brush == nullptr) {
        throw winrt::hresult_invalid_argument(L"the theme resource " + key + L" is not a brush");
    }
    return brush;
}

namespace {

// Whether `current` already paints what `wanted` would (the same solid color, or the same brush).
bool samePaint(media::Brush const &current, media::Brush const &wanted) {
    if (current == wanted) {
        return true;
    }
    media::SolidColorBrush currentSolid = current != nullptr ? current.try_as<media::SolidColorBrush>() : nullptr;
    media::SolidColorBrush wantedSolid = wanted != nullptr ? wanted.try_as<media::SolidColorBrush>() : nullptr;
    return currentSolid != nullptr && wantedSolid != nullptr && currentSolid.Color() == wantedSolid.Color()
        && currentSolid.Opacity() == wantedSolid.Opacity();
}

} // namespace

// The theme resources a control takes its accent from, and the share of the accent's opacity each
// has (WinUI's accent fills: the default, the secondary at 90 percent when pointed at, the tertiary at
// 80 percent when pressed). Read from microsoft-ui-xaml's theme resources; the disabled ones and the
// text drawn on the accent stay the theme's.
struct AccentKey {
    const wchar_t *key;
    double opacity;
};
const AccentKey accentKeys[] = {
    {L"AccentFillColorDefaultBrush", 1.0}, {L"AccentFillColorSecondaryBrush", 0.9}, {L"AccentFillColorTertiaryBrush", 0.8},
    {L"AccentTextFillColorPrimaryBrush", 1.0}, {L"AccentTextFillColorSecondaryBrush", 0.9}, {L"AccentTextFillColorTertiaryBrush", 0.8},
    {L"ToggleSwitchFillOn", 1.0}, {L"ToggleSwitchFillOnPointerOver", 0.9}, {L"ToggleSwitchFillOnPressed", 0.8},
    {L"ToggleSwitchStrokeOn", 1.0}, {L"ToggleSwitchStrokeOnPointerOver", 0.9}, {L"ToggleSwitchStrokeOnPressed", 0.8},
    {L"CheckBoxCheckBackgroundFillChecked", 1.0}, {L"CheckBoxCheckBackgroundFillCheckedPointerOver", 0.9},
    {L"CheckBoxCheckBackgroundFillCheckedPressed", 0.8},
    {L"CheckBoxCheckBackgroundStrokeChecked", 1.0}, {L"CheckBoxCheckBackgroundStrokeCheckedPointerOver", 0.9},
    {L"CheckBoxCheckBackgroundStrokeCheckedPressed", 0.8},
    {L"CheckBoxCheckBackgroundFillIndeterminate", 1.0}, {L"CheckBoxCheckBackgroundFillIndeterminatePointerOver", 0.9},
    {L"CheckBoxCheckBackgroundFillIndeterminatePressed", 0.8},
    {L"CheckBoxCheckBackgroundStrokeIndeterminate", 1.0}, {L"CheckBoxCheckBackgroundStrokeIndeterminatePointerOver", 0.9},
    {L"CheckBoxCheckBackgroundStrokeIndeterminatePressed", 0.8},
    {L"RadioButtonOuterEllipseCheckedFill", 1.0}, {L"RadioButtonOuterEllipseCheckedFillPointerOver", 0.9},
    {L"RadioButtonOuterEllipseCheckedFillPressed", 0.8},
    {L"RadioButtonOuterEllipseCheckedStroke", 1.0}, {L"RadioButtonOuterEllipseCheckedStrokePointerOver", 0.9},
    {L"RadioButtonOuterEllipseCheckedStrokePressed", 0.8},
    {L"SliderThumbBackground", 1.0}, {L"SliderThumbBackgroundPointerOver", 0.9}, {L"SliderThumbBackgroundPressed", 0.8},
    {L"SliderTrackValueFill", 1.0}, {L"SliderTrackValueFillPointerOver", 0.9}, {L"SliderTrackValueFillPressed", 0.8},
    {L"AccentButtonBackground", 1.0}, {L"AccentButtonBackgroundPointerOver", 0.9}, {L"AccentButtonBackgroundPressed", 0.8},
    {L"HyperlinkButtonForeground", 1.0}, {L"HyperlinkButtonForegroundPointerOver", 0.9}, {L"HyperlinkButtonForegroundPressed", 0.8},
    {L"ProgressBarForeground", 1.0}, {L"ProgressRingForegroundThemeBrush", 1.0},
    {L"SelectorBarItemPillFill", 1.0},
    // A menu Picker's selected item, a List's selection (WinUI keeps it opaque when pointed at and
    // pressed), and the graphical DatePicker's calendar.
    {L"ComboBoxItemPillFillBrush", 1.0},
    {L"ListViewItemSelectionIndicatorBrush", 1.0}, {L"ListViewItemSelectionIndicatorPointerOverBrush", 1.0},
    {L"ListViewItemSelectionIndicatorPressedBrush", 1.0},
    {L"ListViewItemCheckBoxSelectedBrush", 1.0}, {L"ListViewItemCheckBoxSelectedPointerOverBrush", 0.9},
    {L"ListViewItemCheckBoxSelectedPressedBrush", 0.8},
    {L"CalendarViewSelectedBorderBrush", 1.0}, {L"CalendarViewSelectedHoverBorderBrush", 0.9},
    {L"CalendarViewSelectedForeground", 1.0},
    {L"CalendarViewTodayBackground", 1.0}, {L"CalendarViewTodayHoverBackground", 0.9},
    {L"CalendarViewTodayPressedBackground", 0.8},
};

extern "C" {

bool actionUIWinUIElementSetAccent(ActionUIWinUIObject *element, const ActionUIWinUIColor *color) {
    return guarded("element set accent", [&]() {
        mux::FrameworkElement typed = objectAs<mux::FrameworkElement>(element, L"FrameworkElement");
        mux::ResourceDictionary resources = typed.Resources();
        for (AccentKey const &entry : accentKeys) {
            wf::IInspectable key = winrt::box_value(entry.key);
            if (resources.HasKey(key)) {
                resources.Remove(key);
            }
            if (color != nullptr) {
                winrt::Windows::UI::Color value{channel(color->alpha * entry.opacity), channel(color->red),
                                                channel(color->green), channel(color->blue)};
                resources.Insert(key, media::SolidColorBrush(value));
            }
        }
        return true;
    });
}

bool actionUIWinUIElementSetBrush(ActionUIWinUIObject *element, ActionUIWinUIBrushProperty property,
                                  const ActionUIWinUIColor *color, const char *themeBrush) {
    return guarded("element set brush", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        media::Brush wanted = brushFor(color, themeBrush);
        if (property == ActionUIWinUIBrushBackground) {
            // No paint clears the local value, as for the foreground: a control's default
            // background comes from its style, which a null local value would hide.
            if (muxc::Panel panel = typed.try_as<muxc::Panel>(); panel != nullptr) {
                if (wanted == nullptr) {
                    panel.ClearValue(muxc::Panel::BackgroundProperty());
                } else if (!samePaint(panel.Background(), wanted)) {
                    panel.Background(wanted);
                }
                return true;
            }
            if (muxc::Control control = typed.try_as<muxc::Control>(); control != nullptr) {
                if (wanted == nullptr) {
                    control.ClearValue(muxc::Control::BackgroundProperty());
                } else if (!samePaint(control.Background(), wanted)) {
                    control.Background(wanted);
                }
                return true;
            }
            // A rounded box (actionUIWinUIRoundedBoxCreate), which paints its rounded shape.
            if (muxc::Border border = typed.try_as<muxc::Border>(); border != nullptr) {
                if (wanted == nullptr) {
                    border.ClearValue(muxc::Border::BackgroundProperty());
                } else if (!samePaint(border.Background(), wanted)) {
                    border.Background(wanted);
                }
                return true;
            }
            return fail("element set brush", "the element has no background");
        }
        if (property == ActionUIWinUIBrushForeground) {
            if (muxc::TextBlock text = typed.try_as<muxc::TextBlock>(); text != nullptr) {
                if (wanted == nullptr) {
                    text.ClearValue(muxc::TextBlock::ForegroundProperty());
                } else if (!samePaint(text.Foreground(), wanted)) {
                    text.Foreground(wanted);
                }
                return true;
            }
            if (muxc::Control control = typed.try_as<muxc::Control>(); control != nullptr) {
                if (wanted == nullptr) {
                    control.ClearValue(muxc::Control::ForegroundProperty());
                } else if (!samePaint(control.Foreground(), wanted)) {
                    control.Foreground(wanted);
                }
                return true;
            }
            // A symbol (a PathIcon): without its own, it draws in the inherited text color.
            if (muxc::IconElement icon = typed.try_as<muxc::IconElement>(); icon != nullptr) {
                if (wanted == nullptr) {
                    icon.ClearValue(muxc::IconElement::ForegroundProperty());
                } else if (!samePaint(icon.Foreground(), wanted)) {
                    icon.Foreground(wanted);
                }
                return true;
            }
            return fail("element set brush", "the element has no foreground");
        }
        if (property == ActionUIWinUIBrushFill || property == ActionUIWinUIBrushStroke) {
            winrt::Microsoft::UI::Xaml::Shapes::Shape shape = typed.try_as<winrt::Microsoft::UI::Xaml::Shapes::Shape>();
            if (shape == nullptr) {
                return fail("element set brush", "the element is not a shape");
            }
            media::Brush current = property == ActionUIWinUIBrushFill ? shape.Fill() : shape.Stroke();
            if (!samePaint(current, wanted)) {
                if (property == ActionUIWinUIBrushFill) {
                    shape.Fill(wanted);
                } else {
                    shape.Stroke(wanted);
                }
            }
            return true;
        }
        return fail("element set brush", "unknown brush property");
    });
}

bool actionUIWinUIElementSetFont(ActionUIWinUIObject *element, const char *family, double size, int32_t weight) {
    return guarded("element set font", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        muxc::TextBlock text = typed.try_as<muxc::TextBlock>();
        muxc::Control control = text == nullptr ? typed.try_as<muxc::Control>() : nullptr;
        if (text == nullptr && control == nullptr) {
            return fail("element set font", "the element shows no text");
        }
        // Each part: the given value, else the element's default (cleared, so the theme's applies).
        bool hasFamily = family != nullptr && family[0] != '\0';
        bool hasSize = std::isfinite(size) && size > 0;
        bool hasWeight = weight >= 1 && weight <= 999;
        if (text != nullptr) {
            if (hasFamily) {
                text.FontFamily(media::FontFamily(toHString(family)));
            } else {
                text.ClearValue(muxc::TextBlock::FontFamilyProperty());
            }
            if (hasSize) {
                text.FontSize(size);
            } else {
                text.ClearValue(muxc::TextBlock::FontSizeProperty());
            }
            if (hasWeight) {
                text.FontWeight(winrt::Windows::UI::Text::FontWeight{static_cast<uint16_t>(weight)});
            } else {
                text.ClearValue(muxc::TextBlock::FontWeightProperty());
            }
        } else {
            if (hasFamily) {
                control.FontFamily(media::FontFamily(toHString(family)));
            } else {
                control.ClearValue(muxc::Control::FontFamilyProperty());
            }
            if (hasSize) {
                control.FontSize(size);
            } else {
                control.ClearValue(muxc::Control::FontSizeProperty());
            }
            if (hasWeight) {
                control.FontWeight(winrt::Windows::UI::Text::FontWeight{static_cast<uint16_t>(weight)});
            } else {
                control.ClearValue(muxc::Control::FontWeightProperty());
            }
        }
        return true;
    });
}

bool actionUIWinUIElementSetOpacity(ActionUIWinUIObject *element, double opacity) {
    return guarded("element set opacity", [&]() {
        double clamped = std::isfinite(opacity) ? (opacity < 0 ? 0.0 : (opacity > 1 ? 1.0 : opacity)) : 1.0;
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        if (typed.Opacity() != clamped) {
            typed.Opacity(clamped);
        }
        return true;
    });
}

bool actionUIWinUIElementSetHitTestVisible(ActionUIWinUIObject *element, bool visible) {
    return guarded("element set hit test visible", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        if (typed.IsHitTestVisible() != visible) {
            typed.IsHitTestVisible(visible);
        }
        return true;
    });
}

bool actionUIWinUIElementSetCollapsed(ActionUIWinUIObject *element, bool collapsed) {
    return guarded("element set collapsed", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        mux::Visibility wanted = collapsed ? mux::Visibility::Collapsed : mux::Visibility::Visible;
        if (typed.Visibility() != wanted) {
            typed.Visibility(wanted);
        }
        return true;
    });
}

bool actionUIWinUIElementSetEnabled(ActionUIWinUIObject *element, bool enabled) {
    return guarded("element set enabled", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        // Set even when IsEnabled already reads `enabled`: under a disabled parent control (a
        // ScrollViewer) it reads false whatever the control's own value, which must still become
        // false, or the control comes back enabled with its parent.
        if (muxc::Control control = typed.try_as<muxc::Control>(); control != nullptr) {
            control.IsEnabled(enabled);
        }
        return true;
    });
}

bool actionUIWinUIControlSetPadding(ActionUIWinUIObject *control, double leading, double top, double trailing, double bottom) {
    return guarded("control set padding", [&]() {
        if (!(std::isfinite(leading) && std::isfinite(top) && std::isfinite(trailing) && std::isfinite(bottom) && leading >= 0 &&
              top >= 0 && trailing >= 0 && bottom >= 0)) {
            return fail("control set padding", "a padding is not a number of pixels");
        }
        muxc::Control typed = objectAs<muxc::Control>(control, L"Control");
        mux::Thickness wanted{leading, top, trailing, bottom};
        mux::Thickness shown = typed.Padding();
        if (shown.Left != wanted.Left || shown.Top != wanted.Top || shown.Right != wanted.Right || shown.Bottom != wanted.Bottom) {
            typed.Padding(wanted);
        }
        return true;
    });
}

bool actionUIWinUIElementSetAccessibilityHidden(ActionUIWinUIObject *element, bool hidden) {
    return guarded("element set accessibility hidden", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        mux::Automation::Peers::AccessibilityView view =
            hidden ? mux::Automation::Peers::AccessibilityView::Raw : mux::Automation::Peers::AccessibilityView::Content;
        if (mux::Automation::AutomationProperties::GetAccessibilityView(typed) != view) {
            mux::Automation::AutomationProperties::SetAccessibilityView(typed, view);
        }
        return true;
    });
}

bool actionUIWinUIElementSetAccessibleName(ActionUIWinUIObject *element, const char *name) {
    return guarded("element set accessible name", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        winrt::hstring wanted = name != nullptr ? toHString(name) : winrt::hstring{};
        if (mux::Automation::AutomationProperties::GetName(typed) != wanted) {
            mux::Automation::AutomationProperties::SetName(typed, wanted);
        }
        return true;
    });
}

bool actionUIWinUIElementSetAccessibilityHint(ActionUIWinUIObject *element, const char *hint) {
    return guarded("element set accessibility hint", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        winrt::hstring wanted = hint != nullptr ? toHString(hint) : winrt::hstring{};
        if (mux::Automation::AutomationProperties::GetHelpText(typed) != wanted) {
            mux::Automation::AutomationProperties::SetHelpText(typed, wanted);
        }
        return true;
    });
}

bool actionUIWinUIElementSetAccessibilityIdentifier(ActionUIWinUIObject *element, const char *identifier) {
    return guarded("element set accessibility identifier", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        winrt::hstring wanted = identifier != nullptr ? toHString(identifier) : winrt::hstring{};
        if (mux::Automation::AutomationProperties::GetAutomationId(typed) != wanted) {
            mux::Automation::AutomationProperties::SetAutomationId(typed, wanted);
        }
        return true;
    });
}

bool actionUIWinUIElementSetToolTip(ActionUIWinUIObject *element, const char *text) {
    return guarded("element set tool tip", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        if (text == nullptr || text[0] == '\0') {
            typed.ClearValue(muxc::ToolTipService::ToolTipProperty());
        } else {
            muxc::ToolTipService::SetToolTip(typed, winrt::box_value(toHString(text)));
        }
        return true;
    });
}

bool actionUIWinUIElementSetKeyboardShortcut(ActionUIWinUIObject *element, int32_t key, uint32_t modifiers,
                                             const char *text) {
    return guarded("element set keyboard shortcut", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        // ActionUI's only: the element's accelerators are the one this sets.
        typed.KeyboardAccelerators().Clear();
        if (key == 0) {
            typed.ClearValue(mux::Automation::AutomationProperties::AcceleratorKeyProperty());
            return true;
        }
        // A Button's or a switch's automation peer reports only this property as its accelerator key.
        mux::Automation::AutomationProperties::SetAcceleratorKey(typed, text != nullptr ? toHString(text) : winrt::hstring{});
        mux::Input::KeyboardAccelerator accelerator;
        accelerator.Key(static_cast<winrt::Windows::System::VirtualKey>(key));
        accelerator.Modifiers(static_cast<winrt::Windows::System::VirtualKeyModifiers>(modifiers));
        typed.KeyboardAccelerators().Append(accelerator);
        return true;
    });
}

char *actionUIWinUIElementCopyAutomationText(ActionUIWinUIObject *element, ActionUIWinUIAutomationText which) {
    char *copy = nullptr;
    guarded("element copy automation text", [&]() {
        mux::UIElement typed = objectAs<mux::UIElement>(element, L"UIElement");
        mux::Automation::Peers::AutomationPeer peer =
            mux::Automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(typed);
        if (peer == nullptr) {
            return fail("element copy automation text", "the element has no automation peer");
        }
        winrt::hstring text;
        switch (which) {
        case ActionUIWinUIAutomationName:
            text = peer.GetName();
            break;
        case ActionUIWinUIAutomationHelpText:
            text = peer.GetHelpText();
            break;
        case ActionUIWinUIAutomationIdentifier:
            text = peer.GetAutomationId();
            break;
        case ActionUIWinUIAutomationAcceleratorKey:
            text = peer.GetAcceleratorKey();
            break;
        default:
            return fail("element copy automation text", "unknown automation text");
        }
        std::string utf8 = winrt::to_string(text);
        copy = static_cast<char *>(malloc(utf8.size() + 1));
        if (copy == nullptr) {
            return fail("element copy automation text", "out of memory");
        }
        memcpy(copy, utf8.data(), utf8.size() + 1);
        return true;
    });
    return copy;
}

bool actionUIWinUIControlSetJoined(ActionUIWinUIObject *control, bool first, bool last) {
    return guarded("control set joined", [&]() {
        muxc::Control typed = objectAs<muxc::Control>(control, L"Control");
        // The theme's radius and border, else WinUI's defaults (4 and 1).
        mux::CornerRadius radius{4, 4, 4, 4};
        mux::Thickness border{1, 1, 1, 1};
        try {
            mux::ResourceDictionary resources = mux::Application::Current().Resources();
            if (auto found = resources.Lookup(winrt::box_value(L"ControlCornerRadius")).try_as<mux::CornerRadius>()) {
                radius = *found;
            }
            if (auto found = resources.Lookup(winrt::box_value(L"ButtonBorderThemeThickness")).try_as<mux::Thickness>()) {
                border = *found;
            }
        } catch (winrt::hresult_error const &) {
        }
        mux::CornerRadius corners{first ? radius.TopLeft : 0, last ? radius.TopRight : 0, last ? radius.BottomRight : 0,
                                  first ? radius.BottomLeft : 0};
        mux::Thickness edges{first ? border.Left : 0, border.Top, border.Right, border.Bottom};
        typed.CornerRadius(corners);
        typed.BorderThickness(edges);
        return true;
    });
}

} // extern "C"
