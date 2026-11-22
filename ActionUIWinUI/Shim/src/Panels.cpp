// Panels: the application's alert as a ContentDialog, and the nested message loop that makes the C API's
// alert and file panel calls synchronous (as NSAlert.runModal on macOS, a nested GLib loop on Linux).

#include "ShimInternal.h"

#include <memory>
#include <optional>
#include <vector>

#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // ButtonBase's Click
#include <winrt/Windows.System.h>  // VirtualKey
#include <winrt/Microsoft.UI.Xaml.Input.h>  // KeyRoutedEventArgs
#include <winrt/Microsoft.UI.Xaml.Media.h>  // VisualTreeHelper

using namespace actionui_winui;

namespace {

// One alert on screen: its buttons' places in the dialog and the answer, given to the completion once.
struct AlertState {
    ActionUIWinUIAlertCompletion completion = nullptr;
    void *context = nullptr;
    // The button Escape answers (-1: Escape does nothing).
    int32_t escapeIndex = -1;
    // The buttons in the dialog's secondary and close places (-1: none there).
    int32_t secondaryIndex = -1;
    int32_t closeIndex = -1;
    // The button chosen, once known before the dialog closes (a click on the close button or on a button
    // in the content, Escape).
    std::optional<int32_t> answer;
    bool finished = false;
    // The dialog's first focus, given to a button in the content, went to the primary button.
    bool firstFocusMoved = false;
    winrt::weak_ref<muxc::ContentDialog> dialog;

    void finish(int32_t index) {
        if (finished) {
            return;
        }
        finished = true;
        completion(context, index);
    }
};

// The alerts on screen, for actionUIWinUIAlertDismiss.
std::vector<std::shared_ptr<AlertState>> g_alerts;

void forget(AlertState const *state) {
    for (auto iterator = g_alerts.begin(); iterator != g_alerts.end(); ++iterator) {
        if (iterator->get() == state) {
            g_alerts.erase(iterator);
            return;
        }
    }
}

// Shows the dialog over `root` and connects its answer to `state`. Throws when another dialog is open
// there (WinUI shows one at a time in a window).
void present(muxc::ContentDialog const &dialog, mux::XamlRoot const &root, std::shared_ptr<AlertState> const &state) {
    dialog.XamlRoot(root);
    auto operation = dialog.ShowAsync();
    operation.Completed([state](auto const &done, auto) {
        int32_t index = -1;
        if (state->answer) {
            index = *state->answer;
        } else {
            try {
                switch (done.GetResults()) {
                case muxc::ContentDialogResult::Primary: index = 0; break;
                case muxc::ContentDialogResult::Secondary: index = state->secondaryIndex; break;
                default: index = -1; break;
                }
            } catch (winrt::hresult_error const &) {
                index = -1;
            }
        }
        forget(state.get());
        state->finish(index);
    });
}

// The Windows App SDK's ContentPreTranslateMessage, which WinUI's own message loop calls before
// TranslateMessage (keyboard accelerators, access keys, focus navigation): looked up in the runtime's
// modules already loaded, as no import library is documented for it; NULL when none exports it.
using PreTranslate = BOOL(WINAPI *)(const MSG *);
PreTranslate contentPreTranslate() {
    static PreTranslate found = []() -> PreTranslate {
        const wchar_t *const modules[] = {L"Microsoft.UI.Windowing.Core.dll", L"Microsoft.Internal.FrameworkUdk.dll",
                                          L"Microsoft.UI.Input.dll", L"Microsoft.UI.Xaml.dll"};
        for (const wchar_t *name : modules) {
            if (HMODULE module = GetModuleHandleW(name); module != nullptr) {
                if (FARPROC address = GetProcAddress(module, "ContentPreTranslateMessage"); address != nullptr) {
                    return reinterpret_cast<PreTranslate>(address);
                }
            }
        }
        return nullptr;
    }();
    return found;
}

// The first descendant of `node` named `name`, else nullptr.
mux::FrameworkElement findNamed(mux::DependencyObject const &node, winrt::hstring const &name) {
    int32_t count = mux::Media::VisualTreeHelper::GetChildrenCount(node);
    for (int32_t index = 0; index < count; index++) {
        mux::DependencyObject child = mux::Media::VisualTreeHelper::GetChild(node, index);
        if (mux::FrameworkElement element = child.try_as<mux::FrameworkElement>(); element != nullptr && element.Name() == name) {
            return element;
        }
        if (mux::FrameworkElement found = findNamed(child, name); found != nullptr) {
            return found;
        }
    }
    return nullptr;
}

} // namespace

extern "C" {

bool actionUIWinUIRunNestedLoop(const volatile bool *done) {
    if (done == nullptr) {
        return fail("run nested loop", "the flag is NULL");
    }
    MSG message{};
    while (!*done) {
        BOOL got = GetMessageW(&message, nullptr, 0, 0);
        if (got == 0) {
            // WM_QUIT: given back to the outer loop, which ends the application.
            PostQuitMessage(static_cast<int>(message.wParam));
            return false;
        }
        if (got == -1) {
            return fail("run nested loop", "GetMessage failed");
        }
        if (PreTranslate preTranslate = contentPreTranslate(); preTranslate != nullptr && preTranslate(&message)) {
            continue;
        }
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return true;
}

ActionUIWinUIObject *actionUIWinUIAlertShow(ActionUIWinUIObject *anchor, const char *title, const char *message,
                                            const char *const *buttons, int32_t buttonCount, int32_t escapeIndex,
                                            ActionUIWinUIAlertCompletion completion, void *context) {
    return guardedObject("alert show", [&]() -> ActionUIWinUIObject * {
        if (completion == nullptr) {
            fail("alert show", "the completion is NULL");
            return nullptr;
        }
        if (buttonCount < 1 || buttons == nullptr) {
            fail("alert show", "an alert has at least one button");
            return nullptr;
        }
        for (int32_t index = 0; index < buttonCount; index++) {
            if (buttons[index] == nullptr) {
                fail("alert show", "a button's title is NULL");
                return nullptr;
            }
        }
        mux::UIElement over = objectAs<mux::UIElement>(anchor, L"UIElement");
        mux::XamlRoot root = over.XamlRoot();
        // A window's content gets its XamlRoot as the window first loads it (a window just made for the
        // alert, or presented in the same call): the alert waits for that.
        mux::FrameworkElement waitFor = root == nullptr ? over.try_as<mux::FrameworkElement>() : nullptr;
        if (root == nullptr && waitFor == nullptr) {
            fail("alert show", "the element is not in a window's content");
            return nullptr;
        }
        auto state = std::make_shared<AlertState>();
        state->completion = completion;
        state->context = context;
        state->escapeIndex = (escapeIndex >= 0 && escapeIndex < buttonCount) ? escapeIndex : -1;

        muxc::ContentDialog dialog;
        state->dialog = winrt::make_weak(dialog);
        if (title != nullptr) {
            dialog.Title(winrt::box_value(toHString(title)));
        }
        muxc::StackPanel content;
        content.Spacing(12);
        if (message != nullptr && message[0] != '\0') {
            muxc::TextBlock text;
            text.Text(toHString(message));
            text.TextWrapping(mux::TextWrapping::Wrap);
            content.Children().Append(text);
        }
        // Fluent's places, left to right: the first button is the primary one and the default (Enter);
        // the button Escape answers is the close button; the others take the secondary place, then the
        // close place when Escape answers none, then a column in the content.
        dialog.PrimaryButtonText(toHString(buttons[0]));
        dialog.DefaultButton(muxc::ContentDialogButton::Primary);
        if (state->escapeIndex > 0) {
            state->closeIndex = state->escapeIndex;
        }
        std::vector<int32_t> others;
        for (int32_t index = 1; index < buttonCount; index++) {
            if (index == state->closeIndex) {
                continue;
            }
            if (state->secondaryIndex < 0) {
                state->secondaryIndex = index;
            } else if (state->closeIndex < 0 && index == buttonCount - 1 && others.empty()) {
                state->closeIndex = index;
            } else {
                others.push_back(index);
            }
        }
        if (state->secondaryIndex >= 0) {
            dialog.SecondaryButtonText(toHString(buttons[state->secondaryIndex]));
        }
        if (state->closeIndex >= 0) {
            dialog.CloseButtonText(toHString(buttons[state->closeIndex]));
        }
        if (!others.empty()) {
            muxc::StackPanel column;
            column.Spacing(8);
            std::weak_ptr<AlertState> weak = state;
            for (int32_t index : others) {
                muxc::Button button;
                button.Content(winrt::box_value(toHString(buttons[index])));
                button.HorizontalAlignment(mux::HorizontalAlignment::Stretch);
                button.Click([weak, index](auto &&, auto &&) {
                    std::shared_ptr<AlertState> alert = weak.lock();
                    if (alert == nullptr || alert->finished || alert->answer) {
                        return;
                    }
                    alert->answer = index;
                    if (muxc::ContentDialog shown = alert->dialog.get()) {
                        shown.Hide();
                    }
                });
                column.Children().Append(button);
            }
            content.Children().Append(column);
            // The dialog gives its first focus to the first button in its content, which Enter would then
            // press: that focus goes to the primary (default) button instead, as it is given.
            winrt::weak_ref<muxc::StackPanel> columnRef = winrt::make_weak(column);
            dialog.GettingFocus([weak, columnRef](mux::UIElement const &sender, mux::Input::GettingFocusEventArgs const &args) {
                std::shared_ptr<AlertState> alert = weak.lock();
                muxc::StackPanel buttons = columnRef.get();
                if (alert == nullptr || alert->firstFocusMoved || buttons == nullptr || args.NewFocusedElement() == nullptr) {
                    return;
                }
                if (mux::Media::VisualTreeHelper::GetParent(args.NewFocusedElement()) != buttons) {
                    return;
                }
                alert->firstFocusMoved = true;
                mux::FrameworkElement primary = findNamed(sender, L"PrimaryButton");
                if (primary != nullptr) {
                    args.TrySetNewFocusedElement(primary);
                }
            });
        }
        if (content.Children().Size() > 0) {
            dialog.Content(content);
        }
        std::weak_ptr<AlertState> weak = state;
        // A click on the close button answers it. With no close button, Escape closes the dialog with no
        // result: that answers the Escape button, or is refused when there is none.
        dialog.CloseButtonClick([weak](auto &&, auto &&) {
            if (std::shared_ptr<AlertState> alert = weak.lock(); alert != nullptr && !alert->answer) {
                alert->answer = alert->closeIndex;
            }
        });
        dialog.Closing([weak](auto &&, muxc::ContentDialogClosingEventArgs const &args) {
            std::shared_ptr<AlertState> alert = weak.lock();
            if (alert == nullptr || alert->finished || alert->answer ||
                args.Result() != muxc::ContentDialogResult::None) {
                return;
            }
            if (alert->escapeIndex >= 0) {
                alert->answer = alert->escapeIndex;
            } else {
                args.Cancel(true);
            }
        });
        // ContentDialog answers Escape by clicking its close button when it has one. When that button is
        // not the one Escape answers (the first one does, or none), the key is taken before the dialog
        // sees it.
        if (state->closeIndex >= 0 && state->closeIndex != state->escapeIndex) {
            dialog.PreviewKeyDown([weak](auto &&, mux::Input::KeyRoutedEventArgs const &args) {
                if (args.Key() != winrt::Windows::System::VirtualKey::Escape) {
                    return;
                }
                args.Handled(true);
                std::shared_ptr<AlertState> alert = weak.lock();
                if (alert == nullptr || alert->finished || alert->answer || alert->escapeIndex < 0) {
                    return;
                }
                alert->answer = alert->escapeIndex;
                if (muxc::ContentDialog shown = alert->dialog.get()) {
                    shown.Hide();
                }
            });
        }
        if (root != nullptr) {
            present(dialog, root, state);
        } else {
            auto token = std::make_shared<winrt::event_token>();
            *token = waitFor.Loaded([dialog, state, token](wf::IInspectable const &sender, auto &&) {
                mux::FrameworkElement loaded = sender.as<mux::FrameworkElement>();
                loaded.Loaded(*token);
                if (state->finished) {
                    return;
                }
                try {
                    present(dialog, loaded.XamlRoot(), state);
                } catch (winrt::hresult_error const &error) {
                    fail("alert show", error);
                    forget(state.get());
                    state->finish(-1);
                }
            });
        }
        g_alerts.push_back(state);
        return toObject(dialog);
    });
}

bool actionUIWinUIAlertDismiss(ActionUIWinUIObject *alert) {
    return guarded("alert dismiss", [&]() {
        muxc::ContentDialog dialog = objectAs<muxc::ContentDialog>(alert, L"ContentDialog");
        std::shared_ptr<AlertState> state;
        for (auto const &open : g_alerts) {
            if (open->dialog.get() == dialog) {
                state = open;
                break;
            }
        }
        if (state == nullptr) {
            // Answered already.
            return true;
        }
        forget(state.get());
        state->finish(-1);
        // The dialog's own closing reports nothing more (finished); one still waiting for its window to
        // load is not shown. Its window may be closing already.
        try {
            dialog.Hide();
        } catch (winrt::hresult_error const &) {
        }
        return true;
    });
}

} // extern "C"
