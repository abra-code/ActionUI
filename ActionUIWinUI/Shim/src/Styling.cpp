// Styling.cpp - brushes (backgrounds and foregrounds, from a color or the theme) and fonts, on the
// elements that have them: panels, controls, text blocks; and an element's state: opacity, whether the
// pointer reaches it, whether a control is enabled, whether accessibility tools skip it.

#include "ShimInternal.h"

#include <cmath>

#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Xaml.Automation.h>
#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>

namespace media = winrt::Microsoft::UI::Xaml::Media;

using namespace actionui_winui;

namespace {

uint8_t channel(double value) {
    double clamped = std::isfinite(value) ? (value < 0 ? 0.0 : (value > 1 ? 1.0 : value)) : 0.0;
    return static_cast<uint8_t>(clamped * 255.0 + 0.5);
}

// The brush for `color`, or for the theme resource `themeBrush`; nullptr for neither (the
// element's own default). Throws when the theme has no such brush.
media::Brush brushFor(const ActionUIWinUIColor *color, const char *themeBrush) {
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

extern "C" {

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

} // extern "C"
