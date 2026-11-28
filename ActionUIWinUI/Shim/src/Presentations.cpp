// Presentations: a sheet as a ContentDialog over the window, a popover as a Flyout on an element, the host's
// toast as an InfoBar floating over the window's content.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Automation.Peers.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Windows.UI.Xaml.Interop.h>  // xaml_typename

#include <algorithm>

using namespace actionui_winui;

namespace {

namespace primitives = winrt::Microsoft::UI::Xaml::Controls::Primitives;

// As large as the window lets it be: WinUI's ContentDialog is at most 548 by 756 pixels and its flyout
// presenter 456 wide (their theme resources), where SwiftUI sizes a sheet and a popover by their content.
constexpr double unbounded = 100000;

// The toast's place, as ActionUI's macOS toast: at most 520 wide, 16 from the top and from each side of the
// content. Its shadow's depth, as a flyout's (Fluent's elevation for transient surfaces).
constexpr double toastMaxWidth = 520;
constexpr double toastMargin = 16;
constexpr float toastDepth = 32;

// A theme resource of the application, or nullptr when the theme has none by that name.
wf::IInspectable themeResource(wchar_t const *key) {
    try {
        return mux::Application::Current().Resources().Lookup(winrt::box_value(key));
    } catch (winrt::hresult_error const &) {
        return nullptr;
    }
}

// The toast's InfoBar, the popup's child.
muxc::InfoBar toastBar(ActionUIWinUIObject *toast) {
    muxc::InfoBar bar = objectAs<primitives::Popup>(toast, L"Popup").Child().try_as<muxc::InfoBar>();
    if (bar == nullptr) {
        throw winrt::hresult_invalid_argument(L"the toast has no InfoBar");
    }
    return bar;
}

} // namespace

extern "C" {

ActionUIWinUIObject *actionUIWinUIDialogCreate(ActionUIWinUIObject *content) {
    return guardedObject("dialog create", [&]() {
        mux::UIElement child = objectAs<mux::UIElement>(content, L"UIElement");
        muxc::ContentDialog dialog;
        mux::ResourceDictionary resources = dialog.Resources();
        resources.Insert(winrt::box_value(L"ContentDialogMaxWidth"), winrt::box_value(unbounded));
        resources.Insert(winrt::box_value(L"ContentDialogMaxHeight"), winrt::box_value(unbounded));
        // In a holder that can take the keyboard focus, so the dialog's first focus has somewhere to go
        // when the content has nothing focusable (a sheet of text): Escape, which the dialog handles
        // from its focused content, closes it, as the Linux renderer makes such content focusable.
        muxc::ContentControl holder;
        holder.IsTabStop(true);
        holder.UseSystemFocusVisuals(false);
        holder.HorizontalContentAlignment(mux::HorizontalAlignment::Stretch);
        holder.VerticalContentAlignment(mux::VerticalAlignment::Stretch);
        holder.Content(child);
        dialog.Content(holder);
        return toObject(dialog);
    });
}

bool actionUIWinUIDialogShow(ActionUIWinUIObject *dialog, ActionUIWinUIObject *anchor) {
    return guarded("dialog show", [&]() {
        muxc::ContentDialog typed = objectAs<muxc::ContentDialog>(dialog, L"ContentDialog");
        mux::UIElement over = objectAs<mux::UIElement>(anchor, L"UIElement");
        mux::XamlRoot root = over.XamlRoot();
        if (root == nullptr) {
            return fail("dialog show", "the element is not in a window's content");
        }
        typed.XamlRoot(root);
        // Throws at once when another dialog is open in the window (WinUI shows one at a time); the
        // operation itself completes when the dialog closes (Closed).
        typed.ShowAsync();
        return true;
    });
}

bool actionUIWinUIDialogHide(ActionUIWinUIObject *dialog) {
    return guarded("dialog hide", [&]() {
        objectAs<muxc::ContentDialog>(dialog, L"ContentDialog").Hide();
        return true;
    });
}

bool actionUIWinUIDialogOnClosed(ActionUIWinUIObject *dialog, ActionUIWinUICallback handler, void *context,
                                 ActionUIWinUICallback destroyContext) {
    return registerHandler("dialog on closed", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        objectAs<muxc::ContentDialog>(dialog, L"ContentDialog").Closed([holder](auto &&, auto &&) { holder->fire(); });
    });
}

ActionUIWinUIObject *actionUIWinUIFlyoutCreate(ActionUIWinUIObject *content) {
    return guardedObject("flyout create", [&]() {
        mux::UIElement child = objectAs<mux::UIElement>(content, L"UIElement");
        muxc::Flyout flyout;
        flyout.Content(child);
        // In a window of its own (WinUI 3's default), so it can reach past its window as a macOS popover
        // does; actionUIWinUIFlyoutSetKeptInWindow keeps it in the window's content instead.
        flyout.ShouldConstrainToRootBounds(false);
        mux::Style style(winrt::xaml_typename<muxc::FlyoutPresenter>());
        // On the theme's own presenter style: a FlyoutPresenterStyle replaces it, and what is left
        // under it, the framework's built-in default, has another padding and no rounded corners.
        try {
            wf::IInspectable found =
                mux::Application::Current().Resources().Lookup(winrt::box_value(L"DefaultFlyoutPresenterStyle"));
            if (mux::Style base = found.try_as<mux::Style>(); base != nullptr) {
                style.BasedOn(base);
            }
        } catch (winrt::hresult_error const &) {
        }
        style.Setters().Append(mux::Setter(mux::FrameworkElement::MaxWidthProperty(), winrt::box_value(unbounded)));
        style.Setters().Append(mux::Setter(mux::FrameworkElement::MaxHeightProperty(), winrt::box_value(unbounded)));
        flyout.FlyoutPresenterStyle(style);
        return toObject(flyout);
    });
}

bool actionUIWinUIFlyoutSetKeptInWindow(ActionUIWinUIObject *flyout, bool kept) {
    return guarded("flyout set kept in window", [&]() {
        objectAs<muxc::Flyout>(flyout, L"Flyout").ShouldConstrainToRootBounds(kept);
        return true;
    });
}

bool actionUIWinUIFlyoutShow(ActionUIWinUIObject *flyout, ActionUIWinUIObject *anchor, ActionUIWinUIFlyoutPlacement placement) {
    return guarded("flyout show", [&]() {
        muxc::Flyout typed = objectAs<muxc::Flyout>(flyout, L"Flyout");
        mux::FrameworkElement target = objectAs<mux::FrameworkElement>(anchor, L"FrameworkElement");
        if (target.XamlRoot() == nullptr) {
            return fail("flyout show", "the element is not in a window's content");
        }
        switch (placement) {
        case ActionUIWinUIFlyoutPlacementTop: typed.Placement(primitives::FlyoutPlacementMode::Top); break;
        case ActionUIWinUIFlyoutPlacementBottom: typed.Placement(primitives::FlyoutPlacementMode::Bottom); break;
        case ActionUIWinUIFlyoutPlacementLeft: typed.Placement(primitives::FlyoutPlacementMode::Left); break;
        case ActionUIWinUIFlyoutPlacementRight: typed.Placement(primitives::FlyoutPlacementMode::Right); break;
        default: return fail("flyout show", "unknown placement");
        }
        typed.ShowAt(target);
        return true;
    });
}

bool actionUIWinUIFlyoutHide(ActionUIWinUIObject *flyout) {
    return guarded("flyout hide", [&]() {
        objectAs<muxc::Flyout>(flyout, L"Flyout").Hide();
        return true;
    });
}

bool actionUIWinUIFlyoutOnClosed(ActionUIWinUIObject *flyout, ActionUIWinUICallback handler, void *context,
                                 ActionUIWinUICallback destroyContext) {
    return registerHandler("flyout on closed", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        objectAs<muxc::Flyout>(flyout, L"Flyout").Closed([holder](auto &&, auto &&) { holder->fire(); });
    });
}

ActionUIWinUIObject *actionUIWinUIToastShow(ActionUIWinUIObject *anchor, const char *message, const char *actionTitle) {
    return guardedObject("toast show", [&]() -> ActionUIWinUIObject * {
        mux::FrameworkElement over = objectAs<mux::FrameworkElement>(anchor, L"FrameworkElement");
        if (over.XamlRoot() == nullptr) {
            fail("toast show", "the element is not in a window's content");
            return nullptr;
        }
        muxc::InfoBar bar;
        bar.Message(toHString(message));
        bar.IsOpen(true);
        if (actionTitle != nullptr) {
            muxc::Button action;
            action.Content(winrt::box_value(toHString(actionTitle)));
            bar.ActionButton(action);
        }
        // Floating over the content, as a flyout does: an informational bar's own background is
        // translucent (it is meant to sit in a page), so it is backed by the theme's in-app acrylic, a
        // flyout's background, with a flyout's corners and shadow. Looked up as the toast opens: a theme
        // change while it is shown (a few seconds) keeps the old background.
        wf::IInspectable background = themeResource(L"AcrylicInAppFillColorDefaultBrush");
        if (background == nullptr) {
            background = themeResource(L"SolidBackgroundFillColorBaseBrush");
        }
        if (background != nullptr) {
            bar.Resources().Insert(winrt::box_value(L"InfoBarInformationalSeverityBackgroundBrush"), background);
        }
        if (wf::IInspectable corners = themeResource(L"OverlayCornerRadius"); corners != nullptr) {
            bar.CornerRadius(winrt::unbox_value_or<mux::CornerRadius>(corners, bar.CornerRadius()));
        }
        bar.Shadow(mux::Media::ThemeShadow());
        bar.Translation(winrt::Windows::Foundation::Numerics::float3{0, 0, toastDepth});

        // In the window's content (not a window of its own), so a rendering of the window includes it.
        primitives::Popup popup;
        popup.XamlRoot(over.XamlRoot());
        popup.ShouldConstrainToRootBounds(true);
        popup.IsLightDismissEnabled(false);
        popup.Child(bar);

        // At the top center of the anchor's box, kept there as the anchor or the bar changes size (after a
        // layout pass: nothing here measures, which inside SizeChanged could start a layout cycle).
        winrt::weak_ref<mux::FrameworkElement> weakAnchor = over;
        winrt::weak_ref<primitives::Popup> weakPopup = popup;
        winrt::weak_ref<muxc::InfoBar> weakBar = bar;
        auto place = [weakAnchor, weakPopup, weakBar]() {
            mux::FrameworkElement anchorNow = weakAnchor.get();
            primitives::Popup popupNow = weakPopup.get();
            muxc::InfoBar barNow = weakBar.get();
            if (anchorNow == nullptr || popupNow == nullptr || barNow == nullptr || anchorNow.XamlRoot() == nullptr) {
                return;
            }
            double width = anchorNow.ActualWidth();
            barNow.MaxWidth(std::max(0.0, std::min(toastMaxWidth, width - 2 * toastMargin)));
            // 0 before the bar's first layout; its SizeChanged places it again then.
            double barWidth = barNow.ActualWidth();
            winrt::Windows::Foundation::Point origin =
                anchorNow.TransformToVisual(nullptr).TransformPoint(winrt::Windows::Foundation::Point{0, 0});
            popupNow.HorizontalOffset(origin.X + std::max(0.0, (width - barWidth) / 2));
            popupNow.VerticalOffset(origin.Y + toastMargin);
        };
        place();
        auto anchorSize = std::make_shared<mux::FrameworkElement::SizeChanged_revoker>(
            over.SizeChanged(winrt::auto_revoke, [place](auto &&, auto &&) { place(); }));
        bar.SizeChanged([place](auto &&, auto &&) { place(); });
        // The anchor outlives the toast: its handler goes when the toast closes.
        popup.Closed([anchorSize](auto &&, auto &&) { anchorSize->revoke(); });
        // InfoBar announces its opening from OnApplyTemplate only through a peer that already exists
        // (FromElement, which makes none): a new bar has none yet, so it is made here.
        mux::Automation::Peers::FrameworkElementAutomationPeer::CreatePeerForElement(bar);
        popup.IsOpen(true);
        return toObject(popup);
    });
}

bool actionUIWinUIToastHide(ActionUIWinUIObject *toast) {
    return guarded("toast hide", [&]() {
        objectAs<primitives::Popup>(toast, L"Popup").IsOpen(false);
        return true;
    });
}

bool actionUIWinUIToastOnAction(ActionUIWinUIObject *toast, ActionUIWinUICallback handler, void *context,
                                ActionUIWinUICallback destroyContext) {
    return registerHandler("toast on action", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        primitives::ButtonBase action = toastBar(toast).ActionButton();
        if (action == nullptr) {
            throw winrt::hresult_invalid_argument(L"the toast has no action button");
        }
        action.Click([holder](auto &&, auto &&) { holder->fire(); });
    });
}

bool actionUIWinUIToastOnClosed(ActionUIWinUIObject *toast, ActionUIWinUICallback handler, void *context,
                                ActionUIWinUICallback destroyContext) {
    return registerHandler("toast on closed", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        toastBar(toast).Closed([holder](auto &&, muxc::InfoBarClosedEventArgs const &args) {
            // The user's close button only, not the toast being taken down.
            if (args.Reason() == muxc::InfoBarCloseReason::CloseButton) {
                holder->fire();
            }
        });
    });
}

} // extern "C"
