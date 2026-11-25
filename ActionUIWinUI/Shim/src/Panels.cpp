// Panels: the application's alert as a ContentDialog, the nested message loop that makes the C API's alert
// call synchronous (as NSAlert.runModal on macOS, a nested GLib loop on Linux), and the system's file
// dialogs (IFileOpenDialog, IFileSaveDialog): synchronous on their own, or each on a thread of its own for
// a host that serves other work meanwhile.

#include "ShimInternal.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>
#include <vector>

#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // ButtonBase's Click
#include <winrt/Windows.System.h>  // VirtualKey
#include <winrt/Microsoft.UI.Xaml.Input.h>  // KeyRoutedEventArgs
#include <winrt/Microsoft.UI.Xaml.Media.h>  // VisualTreeHelper

#include <microsoft.ui.xaml.window.h>  // IWindowNative: the window's HWND
#include <shobjidl.h>                  // IFileOpenDialog, IFileSaveDialog

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

// The file dialogs on screen, for actionUIWinUIFileDialogsClose: each with the window it is modal to.
struct OpenFileDialog {
    IFileDialog *dialog;
    HWND owner;
};
std::vector<OpenFileDialog> g_fileDialogs;

// "C:/a/b" as Windows writes it, "C:\a\b": the shell's parser reads only backslashes.
std::wstring backslashed(const char *utf8) {
    std::wstring path(toHString(utf8));
    for (wchar_t &character : path) {
        if (character == L'/') {
            character = L'\\';
        }
    }
    return path;
}

// The file-system path of `item`, else an empty string (an item with no path: the dialog's
// FOS_FORCEFILESYSTEM leaves none).
std::wstring pathOf(IShellItem *item) {
    PWSTR path = nullptr;
    std::wstring copy;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path != nullptr) {
        copy = path;
        CoTaskMemFree(path);
    }
    return copy;
}

// A new UTF-8 copy of `text` (malloc), or nullptr when out of memory.
char *copyUTF8(std::wstring const &text) {
    std::string utf8 = winrt::to_string(text);
    char *copy = static_cast<char *>(malloc(utf8.size() + 1));
    if (copy != nullptr) {
        memcpy(copy, utf8.c_str(), utf8.size() + 1);
    }
    return copy;
}

// A file dialog's settings, copied from the C call's arguments: for a dialog shown at once
// (actionUIWinUIFileDialogRun) or on a thread of its own (actionUIWinUIFileDialogBegin).
struct FileDialogRequest {
    ActionUIWinUIFileDialogKind kind = ActionUIWinUIFileDialogKindOpen;
    bool multiple = false;
    std::wstring title;
    std::wstring okLabel;
    std::wstring folder;
    std::optional<std::wstring> fileName;
    std::vector<std::wstring> filterNames;
    std::vector<std::wstring> filterPatterns;
    std::wstring defaultExtension;
    bool strictTypes = false;

    bool saving() const {
        return kind == ActionUIWinUIFileDialogKindSave;
    }
};

// The request the C arguments describe (see actionUIWinUIFileDialogRun); false, with an error recorded for
// `where`, when they are malformed.
bool readFileDialogRequest(const char *where, ActionUIWinUIFileDialogKind kind, bool multiple, const char *title,
                           const char *okLabel, const char *folder, const char *fileName, const char *const *filterNames,
                           const char *const *filterPatterns, int32_t filterCount, const char *defaultExtension,
                           bool strictTypes, FileDialogRequest &request) {
    if (filterCount < 0 || (filterCount > 0 && (filterNames == nullptr || filterPatterns == nullptr))) {
        return fail(where, "the filters are missing");
    }
    request.kind = kind;
    request.multiple = multiple;
    if (title != nullptr) {
        request.title = std::wstring(toHString(title));
    }
    if (okLabel != nullptr) {
        request.okLabel = std::wstring(toHString(okLabel));
    }
    if (folder != nullptr) {
        request.folder = backslashed(folder);
    }
    if (fileName != nullptr) {
        request.fileName = std::wstring(toHString(fileName));
    }
    if (kind != ActionUIWinUIFileDialogKindOpenFolder) {
        for (int32_t index = 0; index < filterCount; index++) {
            if (filterNames[index] == nullptr || filterPatterns[index] == nullptr) {
                return fail(where, "a filter's name or pattern is NULL");
            }
            request.filterNames.emplace_back(toHString(filterNames[index]));
            request.filterPatterns.emplace_back(toHString(filterPatterns[index]));
        }
    }
    if (defaultExtension != nullptr) {
        request.defaultExtension = std::wstring(toHString(defaultExtension));
    }
    request.strictTypes = strictTypes;
    return true;
}

// A new dialog set up as `request` asks, not shown. Throws on failure.
winrt::com_ptr<IFileDialog> makeFileDialog(FileDialogRequest const &request) {
    winrt::com_ptr<IFileDialog> dialog;
    if (request.saving()) {
        dialog = winrt::create_instance<IFileDialog>(__uuidof(FileSaveDialog), CLSCTX_INPROC_SERVER);
    } else {
        dialog = winrt::create_instance<IFileDialog>(__uuidof(FileOpenDialog), CLSCTX_INPROC_SERVER);
    }
    FILEOPENDIALOGOPTIONS options = 0;
    winrt::check_hresult(dialog->GetOptions(&options));
    // Paths only (no library or network item without one); the folder the program runs in stays.
    options |= FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR | FOS_PATHMUSTEXIST;
    if (request.saving()) {
        options |= FOS_OVERWRITEPROMPT;
        if (request.strictTypes) {
            // The chosen filter's extension is added to a name with another one, before the dialog asks
            // about replacing a file: it asks about the file saved.
            options |= FOS_STRICTFILETYPES;
        }
    } else {
        options |= FOS_FILEMUSTEXIST;
        if (request.kind == ActionUIWinUIFileDialogKindOpenFolder) {
            options |= FOS_PICKFOLDERS;
        }
        if (request.multiple) {
            options |= FOS_ALLOWMULTISELECT;
        }
    }
    winrt::check_hresult(dialog->SetOptions(options));
    if (!request.title.empty()) {
        winrt::check_hresult(dialog->SetTitle(request.title.c_str()));
    }
    if (!request.okLabel.empty()) {
        winrt::check_hresult(dialog->SetOkButtonLabel(request.okLabel.c_str()));
    }
    if (!request.folder.empty()) {
        winrt::com_ptr<IShellItem> start;
        // A folder that is not there leaves the dialog where Windows would open it.
        if (SUCCEEDED(SHCreateItemFromParsingName(request.folder.c_str(), nullptr, IID_PPV_ARGS(start.put())))) {
            // A file, or an item the dialog refuses, leaves it there too.
            dialog->SetFolder(start.get());
        }
    }
    if (request.fileName.has_value()) {
        winrt::check_hresult(dialog->SetFileName(request.fileName->c_str()));
    }
    if (!request.filterNames.empty()) {
        std::vector<COMDLG_FILTERSPEC> specs;
        for (size_t index = 0; index < request.filterNames.size(); index++) {
            specs.push_back({request.filterNames[index].c_str(), request.filterPatterns[index].c_str()});
        }
        winrt::check_hresult(dialog->SetFileTypes(static_cast<UINT>(specs.size()), specs.data()));
        winrt::check_hresult(dialog->SetFileTypeIndex(1));
    }
    if (!request.defaultExtension.empty()) {
        winrt::check_hresult(dialog->SetDefaultExtension(request.defaultExtension.c_str()));
    }
    return dialog;
}

// The paths an answered `dialog` chose, one per line; empty when none has a path (FOS_FORCEFILESYSTEM leaves
// none without one). Throws on failure.
std::wstring chosenPaths(winrt::com_ptr<IFileDialog> const &dialog, FileDialogRequest const &request) {
    std::wstring joined;
    if (!request.saving() && request.multiple) {
        winrt::com_ptr<IShellItemArray> items;
        winrt::check_hresult(dialog.as<IFileOpenDialog>()->GetResults(items.put()));
        DWORD count = 0;
        winrt::check_hresult(items->GetCount(&count));
        for (DWORD index = 0; index < count; index++) {
            winrt::com_ptr<IShellItem> item;
            winrt::check_hresult(items->GetItemAt(index, item.put()));
            std::wstring path = pathOf(item.get());
            if (path.empty()) {
                continue;
            }
            if (!joined.empty()) {
                joined += L'\n';
            }
            joined += path;
        }
    } else {
        winrt::com_ptr<IShellItem> item;
        winrt::check_hresult(dialog->GetResult(item.put()));
        joined = pathOf(item.get());
    }
    return joined;
}

// A file dialog on a thread of its own (actionUIWinUIFileDialogBegin): what its handle's cancel, on the UI
// thread, and the dialog's thread share.
struct FileDialogTask {
    std::mutex lock;
    bool canceled = false;
    // The dialog thread's message-only window while the dialog is shown (or about to be), else nullptr.
    HWND messageWindow = nullptr;
};

// The answer of a dialog on its own thread, handed to the UI thread for its completion.
struct FileDialogAnswer {
    ActionUIWinUIFileDialogCompletion completion = nullptr;
    void *context = nullptr;
    // The chosen paths, one per line; empty: canceled.
    std::wstring chosen;
    // Why the dialog could not be shown; empty: it was.
    std::string failure;
};

// Posted to the message-only window by a cancel; WM_TIMER with this ID tries again.
constexpr UINT cancelDialogMessage = WM_APP + 1;
constexpr UINT_PTR cancelRetryTimer = 1;
constexpr wchar_t cancelWindowClassName[] = L"ActionUIWinUIFileDialogCancel";

// Closes `dialog`, on screen, as its close button does: Show returns ERROR_CANCELLED. False when its window
// is not up yet. IFileDialog::Close returns S_OK and leaves the dialog up (measured) when it is called from
// anywhere but the dialog's own event callbacks.
bool closeUnanswered(IFileDialog *dialog) {
    winrt::com_ptr<IOleWindow> oleWindow;
    HWND dialogWindow = nullptr;
    if (dialog == nullptr || FAILED(dialog->QueryInterface(IID_PPV_ARGS(oleWindow.put()))) ||
        FAILED(oleWindow->GetWindow(&dialogWindow)) || dialogWindow == nullptr) {
        return false;
    }
    PostMessageW(dialogWindow, WM_CLOSE, 0, 0);
    return true;
}

// The message-only window's procedure, on the dialog's thread, which Show's own message loop serves: closes
// the dialog (GWLP_USERDATA) unanswered, and again every 50 ms until Show returns and the window goes (with
// its timer). Again: the cancel can come while Show is still making the dialog, or while the dialog asks
// something of its own (replace the file?), when it is disabled and may not take the close until the user
// answers that.
LRESULT CALLBACK cancelWindowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == cancelDialogMessage || (message == WM_TIMER && wParam == cancelRetryTimer)) {
        closeUnanswered(reinterpret_cast<IFileDialog *>(GetWindowLongPtrW(window, GWLP_USERDATA)));
        if (message == cancelDialogMessage) {
            SetTimer(window, cancelRetryTimer, 50, nullptr);
        }
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

// This DLL's module, which registers the message-only window's class.
HINSTANCE shimModule() {
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&cancelWindowProcedure), &module);
    return module;
}

// Registers the message-only window's class, once for the process. False when it could not be.
bool registerCancelWindowClass() {
    static const bool registered = []() {
        WNDCLASSEXW windowClass{};
        windowClass.cbSize = sizeof(windowClass);
        windowClass.lpfnWndProc = cancelWindowProcedure;
        windowClass.hInstance = shimModule();
        windowClass.lpszClassName = cancelWindowClassName;
        return RegisterClassExW(&windowClass) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    }();
    return registered;
}

// The dialog's thread: its own single-threaded COM apartment (OLE's, for the file list's drag and drop and
// clipboard), the dialog shown with no owner (its own
// message loop runs until the user answers or a cancel closes it), and the answer handed to `queue`'s
// thread for the completion.
void runFileDialogTask(std::shared_ptr<FileDialogTask> task, FileDialogRequest request,
                       dispatching::DispatcherQueue queue, std::shared_ptr<FileDialogAnswer> answer) {
    HRESULT initialized = OleInitialize(nullptr);
    try {
        winrt::check_hresult(initialized);
        winrt::com_ptr<IFileDialog> dialog = makeFileDialog(request);
        if (!registerCancelWindowClass()) {
            winrt::throw_last_error();
        }
        HWND window = CreateWindowExW(0, cancelWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                      shimModule(), nullptr);
        if (window == nullptr) {
            winrt::throw_last_error();
        }
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(dialog.get()));
        bool canceled = false;
        {
            std::lock_guard<std::mutex> guard(task->lock);
            canceled = task->canceled;
            if (!canceled) {
                task->messageWindow = window;
            }
        }
        HRESULT shown = canceled ? HRESULT_FROM_WIN32(ERROR_CANCELLED) : dialog->Show(nullptr);
        {
            // No cancel posts to the window after this.
            std::lock_guard<std::mutex> guard(task->lock);
            task->messageWindow = nullptr;
        }
        DestroyWindow(window);
        if (shown != HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            winrt::check_hresult(shown);
            answer->chosen = chosenPaths(dialog, request);
        }
    } catch (winrt::hresult_error const &error) {
        char code[16];
        snprintf(code, sizeof(code), "0x%08X", static_cast<unsigned>(error.code()));
        std::string message = winrt::to_string(error.message());
        answer->failure = message.empty() ? std::string("the file dialog failed (") + code + ")"
                                          : message + " (" + code + ")";
    } catch (std::exception const &error) {
        answer->failure = error.what();
    } catch (...) {
        answer->failure = "an unknown C++ exception";
    }
    try {
        // Refused when the UI thread's queue is shutting down (the application ending): the completion
        // does not run, and its context is not freed.
        queue.TryEnqueue([answer]() {
            std::string chosen = winrt::to_string(answer->chosen);
            answer->completion(answer->context, answer->chosen.empty() ? nullptr : chosen.c_str(),
                               answer->failure.empty() ? nullptr : answer->failure.c_str());
        });
    } catch (...) {
    }
    // Released while this thread is still in its apartment.
    queue = nullptr;
    if (SUCCEEDED(initialized)) {
        OleUninitialize();
    }
}

} // namespace

// A handle on a file dialog shown on a thread of its own (actionUIWinUIFileDialogBegin).
struct ActionUIWinUIFileDialogTask {
    std::shared_ptr<FileDialogTask> task;
};

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

bool actionUIWinUIFileDialogRun(ActionUIWinUIObject *owner, ActionUIWinUIFileDialogKind kind, bool multiple, const char *title,
                                 const char *okLabel, const char *folder, const char *fileName, const char *const *filterNames,
                                 const char *const *filterPatterns, int32_t filterCount, const char *defaultExtension,
                                 bool strictTypes, char **chosen) {
    return guarded("file dialog run", [&]() {
        if (chosen == nullptr) {
            return fail("file dialog run", "the answer's pointer is NULL");
        }
        *chosen = nullptr;
        FileDialogRequest request;
        if (!readFileDialogRequest("file dialog run", kind, multiple, title, okLabel, folder, fileName, filterNames,
                                   filterPatterns, filterCount, defaultExtension, strictTypes, request)) {
            return false;
        }
        HWND ownerWindow = nullptr;
        if (owner != nullptr) {
            mux::Window window = objectAs<mux::Window>(owner, L"Window");
            winrt::check_hresult(window.as<::IWindowNative>()->get_WindowHandle(&ownerWindow));
        }
        winrt::com_ptr<IFileDialog> dialog = makeFileDialog(request);
        g_fileDialogs.push_back({dialog.get(), ownerWindow});
        HRESULT shown = dialog->Show(ownerWindow);
        for (auto iterator = g_fileDialogs.begin(); iterator != g_fileDialogs.end(); ++iterator) {
            if (iterator->dialog == dialog.get()) {
                g_fileDialogs.erase(iterator);
                break;
            }
        }
        if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            return true;
        }
        winrt::check_hresult(shown);
        std::wstring joined = chosenPaths(dialog, request);
        if (joined.empty()) {
            // Chosen, but nothing with a path: as canceled.
            return true;
        }
        *chosen = copyUTF8(joined);
        if (*chosen == nullptr) {
            return fail("file dialog run", "out of memory");
        }
        return true;
    });
}

void actionUIWinUIFileDialogsClose(ActionUIWinUIObject *owner) {
    guarded("file dialogs close", [&]() {
        HWND ownerWindow = nullptr;
        if (owner != nullptr) {
            mux::Window window = objectAs<mux::Window>(owner, L"Window");
            winrt::check_hresult(window.as<::IWindowNative>()->get_WindowHandle(&ownerWindow));
        }
        for (OpenFileDialog const &open : g_fileDialogs) {
            if (owner == nullptr || open.owner == ownerWindow) {
                closeUnanswered(open.dialog);
            }
        }
        return true;
    });
}

ActionUIWinUIFileDialogTask *actionUIWinUIFileDialogBegin(ActionUIWinUIFileDialogKind kind, bool multiple, const char *title,
                                                          const char *okLabel, const char *folder, const char *fileName,
                                                          const char *const *filterNames, const char *const *filterPatterns,
                                                          int32_t filterCount, const char *defaultExtension, bool strictTypes,
                                                          ActionUIWinUIFileDialogCompletion completion, void *context) {
    ActionUIWinUIFileDialogTask *handle = nullptr;
    guarded("file dialog begin", [&]() {
        if (completion == nullptr) {
            return fail("file dialog begin", "the completion is NULL");
        }
        FileDialogRequest request;
        if (!readFileDialogRequest("file dialog begin", kind, multiple, title, okLabel, folder, fileName, filterNames,
                                   filterPatterns, filterCount, defaultExtension, strictTypes, request)) {
            return false;
        }
        dispatching::DispatcherQueue queue = currentQueue();
        auto task = std::make_shared<FileDialogTask>();
        auto answer = std::make_shared<FileDialogAnswer>();
        answer->completion = completion;
        answer->context = context;
        auto owned = std::make_unique<ActionUIWinUIFileDialogTask>();
        owned->task = task;
        std::thread(runFileDialogTask, task, std::move(request), queue, answer).detach();
        handle = owned.release();
        return true;
    });
    return handle;
}

void actionUIWinUIFileDialogCancel(ActionUIWinUIFileDialogTask *task) {
    guarded("file dialog cancel", [&]() {
        if (task == nullptr) {
            return fail("file dialog cancel", "the dialog is NULL");
        }
        std::lock_guard<std::mutex> guard(task->task->lock);
        task->task->canceled = true;
        if (task->task->messageWindow != nullptr) {
            PostMessageW(task->task->messageWindow, cancelDialogMessage, 0, 0);
        }
        return true;
    });
}

void actionUIWinUIFileDialogRelease(ActionUIWinUIFileDialogTask *task) {
    delete task;
}

} // extern "C"
