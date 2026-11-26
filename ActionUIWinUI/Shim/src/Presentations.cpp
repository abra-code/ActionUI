// Presentations: a sheet as a ContentDialog over the window, a popover as a Flyout on an element.

#include "ShimInternal.h"

#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Windows.UI.Xaml.Interop.h>  // xaml_typename

using namespace actionui_winui;

namespace {

namespace primitives = winrt::Microsoft::UI::Xaml::Controls::Primitives;

// As large as the window lets it be: WinUI's ContentDialog is at most 548 by 756 pixels and its flyout
// presenter 456 wide (their theme resources), where SwiftUI sizes a sheet and a popover by their content.
constexpr double unbounded = 100000;

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

} // extern "C"
