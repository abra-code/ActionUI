// Application.cpp - errors, object references, the runtime bootstrap, the application and its UI
// thread services (delayed calls, Win32 event watches).
//
// A WinUI app without XAML markup: the Application subclass implements IXamlMetadataProvider by
// forwarding to the controls' own provider, which is what the XAML compiler would generate.

#include "ShimInternal.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <cwctype>  // towlower
#include <memory>
#include <vector>

#include <MddBootstrap.h>
#include <WindowsAppSDK-VersionInfo.h>

#include <winrt/Windows.System.h>  // Launcher
#include <winrt/Windows.UI.Xaml.Interop.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>

namespace actionui_winui {

namespace {

thread_local std::string t_lastError;

} // namespace

void setLastError(std::string message) {
    t_lastError = std::move(message);
}

bool fail(const char *where, winrt::hresult_error const &error) {
    char code[16];
    snprintf(code, sizeof(code), "0x%08X", static_cast<unsigned>(error.code().value));
    setLastError(std::string(where) + ": " + winrt::to_string(error.message()) + " (" + code + ")");
    return false;
}

bool fail(const char *where, std::exception const &error) {
    setLastError(std::string(where) + ": " + error.what());
    return false;
}

bool fail(const char *where, const char *message) {
    setLastError(std::string(where) + ": " + message);
    return false;
}

winrt::hstring toHString(const char *utf8) {
    return winrt::to_hstring(std::string_view(utf8 != nullptr ? utf8 : ""));
}

ActionUIWinUIObject *toObject(wf::IInspectable const &value) {
    wf::IInspectable copy = value;
    return static_cast<ActionUIWinUIObject *>(winrt::detach_abi(copy));
}

namespace {

namespace muxm = winrt::Microsoft::UI::Xaml::Markup;

bool g_launchFailed = false;

struct App : mux::ApplicationT<App, muxm::IXamlMetadataProvider> {
    App(ActionUIWinUICallback onLaunched, void *context) : m_onLaunched(onLaunched), m_context(context) {}

    void OnLaunched(mux::LaunchActivatedEventArgs const &) {
        bool ready = guarded("launch", [&]() {
            Resources().MergedDictionaries().Append(muxc::XamlControlsResources());
            return true;
        });
        if (!ready) {
            g_launchFailed = true;
            Exit();
            return;
        }
        // The run ends only at actionUIWinUIQuit: WinUI would end it as the last window closes, where a
        // host may close one window before opening the next.
        guarded("launch", [&]() {
            DispatcherShutdownMode(mux::DispatcherShutdownMode::OnExplicitShutdown);
            return true;
        });
        if (m_onLaunched != nullptr) {
            m_onLaunched(m_context);
        }
    }

    // IXamlMetadataProvider, forwarded to the controls' provider.
    muxm::IXamlType GetXamlType(winrt::Windows::UI::Xaml::Interop::TypeName const &type) {
        return m_provider.GetXamlType(type);
    }
    muxm::IXamlType GetXamlType(winrt::hstring const &fullName) {
        return m_provider.GetXamlType(fullName);
    }
    winrt::com_array<muxm::XmlnsDefinition> GetXmlnsDefinitions() {
        return m_provider.GetXmlnsDefinitions();
    }

private:
    ActionUIWinUICallback m_onLaunched;
    void *m_context;
    mux::XamlTypeInfo::XamlControlsXamlMetaDataProvider m_provider;
};

// Delayed calls waiting for their timer; each removes itself when it fires.
std::vector<dispatching::DispatcherQueueTimer> g_timers;

// A thread-pool wait on a Win32 event that enqueues the callback on the UI thread.
struct HandleWatch : std::enable_shared_from_this<HandleWatch> {
    ActionUIWinUICallback callback = nullptr;
    void *context = nullptr;
    dispatching::DispatcherQueue queue{nullptr};
    HANDLE wait = nullptr;
};
std::vector<std::shared_ptr<HandleWatch>> g_watches;

// On a thread-pool thread, which the wait keeps from running past UnregisterWaitEx. The queued call
// holds only a weak reference: it can still sit in the queue after actionUIWinUIRun has freed the
// watch, and then does nothing.
void CALLBACK onHandleSignaled(PVOID parameter, BOOLEAN) {
    HandleWatch *watch = static_cast<HandleWatch *>(parameter);
    try {
        // Fails quietly once the UI thread's queue has shut down.
        watch->queue.TryEnqueue([weak = watch->weak_from_this()]() {
            std::shared_ptr<HandleWatch> alive = weak.lock();
            if (alive != nullptr) {
                alive->callback(alive->context);
            }
        });
    } catch (...) {
        // No exception may leave a thread-pool callback; this signal is lost.
    }
}

} // namespace

dispatching::DispatcherQueue currentQueue() {
    dispatching::DispatcherQueue queue = dispatching::DispatcherQueue::GetForCurrentThread();
    if (queue == nullptr) {
        throw winrt::hresult_wrong_thread(L"not on the UI thread (no DispatcherQueue)");
    }
    return queue;
}

void callOnUIThread(dispatching::DispatcherQueue const &queue, ActionUIWinUICallback callback, void *context) noexcept {
    if (callback == nullptr) {
        return;
    }
    bool elsewhere = false;
    try {
        elsewhere = queue != nullptr && !queue.HasThreadAccess();
        if (elsewhere) {
            queue.TryEnqueue([callback, context]() { callback(context); });
        }
    } catch (...) {
    }
    if (!elsewhere) {
        callback(context);
    }
}

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

bool actionUIWinUICopyLastError(char *outMessage, ptrdiff_t outMessageSize) {
    if (outMessage == nullptr || outMessageSize <= 0) {
        return false;
    }
    size_t count = t_lastError.size();
    if (count > static_cast<size_t>(outMessageSize - 1)) {
        count = static_cast<size_t>(outMessageSize - 1);
    }
    memcpy(outMessage, t_lastError.data(), count);
    outMessage[count] = '\0';
    return true;
}

bool actionUIWinUIInitialize(void) {
    PACKAGE_VERSION minVersion{};
    minVersion.Version = WINDOWSAPPSDK_RUNTIME_VERSION_UINT64;
    HRESULT result = MddBootstrapInitialize2(WINDOWSAPPSDK_RELEASE_MAJORMINOR, WINDOWSAPPSDK_RELEASE_VERSION_TAG_W,
                                             minVersion, MddBootstrapInitializeOptions_None);
    if (FAILED(result)) {
        char message[160];
        snprintf(message, sizeof(message),
                 "MddBootstrapInitialize2 failed with 0x%08X: is the Windows App SDK %u.%u runtime installed?",
                 static_cast<unsigned>(result), WINDOWSAPPSDK_RELEASE_MAJOR, WINDOWSAPPSDK_RELEASE_MINOR);
        return fail("initialize", message);
    }
    return true;
}

void actionUIWinUIShutdown(void) {
    MddBootstrapShutdown();
}

bool actionUIWinUIRun(ActionUIWinUICallback onLaunched, void *context) {
    g_launchFailed = false;
    bool started = guarded("run", [&]() {
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        mux::Application::Start([onLaunched, context](auto &&) { winrt::make<App>(onLaunched, context); });
        return true;
    });
    // Let go of the UI thread's services now, while this is still the UI thread.
    for (auto &watch : g_watches) {
        if (watch->wait != nullptr) {
            UnregisterWaitEx(watch->wait, INVALID_HANDLE_VALUE);  // waits for a callback in progress
        }
    }
    g_watches.clear();
    // A started timer may stay alive in the queue without our reference: stop it so it cannot fire.
    for (auto &timer : g_timers) {
        try {
            timer.Stop();
        } catch (...) {
        }
    }
    g_timers.clear();
    return started && !g_launchFailed;
}

void actionUIWinUIQuit(void) {
    guarded("quit", []() {
        mux::Application::Current().Exit();
        return true;
    });
}

bool actionUIWinUIApplicationExists(void) {
    // No WinUI loaded, no Application: asked first so the check loads nothing and leaves COM as it was.
    if (GetModuleHandleW(L"Microsoft.UI.Xaml.dll") == nullptr) {
        return false;
    }
    try {
        return mux::Application::Current() != nullptr;
    } catch (...) {
        return false;
    }
}

char *actionUIWinUICopyProgramFolder(void) {
    char *copy = nullptr;
    guarded("copy program folder", [&]() {
        // Longer paths than MAX_PATH: grow until the name fits (GetModuleFileNameW cuts it to the buffer).
        std::wstring path(MAX_PATH, L'\0');
        DWORD length = 0;
        while (true) {
            length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
            if (length == 0) {
                return fail("copy program folder", "GetModuleFileNameW failed");
            }
            if (length < path.size()) {
                break;
            }
            if (path.size() >= 32768) {
                return fail("copy program folder", "the program's path is too long");
            }
            path.resize(path.size() * 2);
        }
        path.resize(length);
        size_t slash = path.find_last_of(L"\\/");
        if (slash == std::wstring::npos) {
            return fail("copy program folder", "the program's path has no folder");
        }
        // "C:\app.exe" or "\\?\C:\app.exe": a drive's root would hold every file on the drive.
        size_t start = path.rfind(L"\\\\?\\", 0) == 0 ? 4 : 0;
        if (slash <= start + 2) {
            return fail("copy program folder", "the program is at the root of a drive");
        }
        std::string utf8 = winrt::to_string(std::wstring_view(path.data(), slash));
        copy = static_cast<char *>(malloc(utf8.size() + 1));
        if (copy == nullptr) {
            return fail("copy program folder", "out of memory");
        }
        memcpy(copy, utf8.c_str(), utf8.size() + 1);
        return true;
    });
    return copy;
}

bool actionUIWinUILaunchURL(const char *url) {
    return guarded("launch url", [&]() {
        if (url == nullptr) {
            return fail("launch url", "the URL is NULL");
        }
        wf::Uri uri(toHString(url));
        // XAML's own rules for a HyperlinkButton's NavigateUri (microsoft-ui-xaml's
        // Launcher::TryInvokeLauncher): file: and res: are not opened; http and https open at once;
        // any other scheme (another app's) opens with Windows' warning before switching apps.
        std::wstring scheme(uri.SchemeName());
        for (wchar_t &character : scheme) {
            character = towlower(character);
        }
        if (scheme == L"file" || scheme == L"res") {
            return fail("launch url", "Windows does not open file: or res: links");
        }
        // Not awaited: the app opens on its own time, as NavigateUri opens it.
        if (scheme == L"http" || scheme == L"https") {
            winrt::Windows::System::Launcher::LaunchUriAsync(uri);
        } else {
            winrt::Windows::System::LauncherOptions options;
            options.TreatAsUntrusted(true);
            winrt::Windows::System::Launcher::LaunchUriAsync(uri, options);
        }
        return true;
    });
}

bool actionUIWinUIPostDelayed(int32_t milliseconds, ActionUIWinUICallback callback, void *context) {
    return guarded("post delayed", [&]() {
        if (callback == nullptr) {
            return fail("post delayed", "the callback is NULL");
        }
        dispatching::DispatcherQueue queue = currentQueue();
        if (milliseconds <= 0) {
            if (!queue.TryEnqueue([callback, context]() { callback(context); })) {
                return fail("post delayed", "the UI thread's queue refused the call (shutting down?)");
            }
            return true;
        }
        dispatching::DispatcherQueueTimer timer = queue.CreateTimer();
        timer.Interval(std::chrono::milliseconds(milliseconds));
        timer.IsRepeating(false);
        timer.Tick([callback, context](dispatching::DispatcherQueueTimer const &sender, auto &&) {
            sender.Stop();
            for (auto iterator = g_timers.begin(); iterator != g_timers.end(); ++iterator) {
                if (*iterator == sender) {
                    g_timers.erase(iterator);
                    break;
                }
            }
            callback(context);
        });
        g_timers.push_back(timer);
        timer.Start();
        return true;
    });
}

bool actionUIWinUIWatchHandle(void *handle, ActionUIWinUICallback onSignaled, void *context) {
    return guarded("watch handle", [&]() {
        if (handle == nullptr || onSignaled == nullptr) {
            return fail("watch handle", "the handle or the callback is NULL");
        }
        auto watch = std::make_shared<HandleWatch>();
        watch->callback = onSignaled;
        watch->context = context;
        watch->queue = currentQueue();
        BOOL registered = RegisterWaitForSingleObject(&watch->wait, static_cast<HANDLE>(handle), onHandleSignaled,
                                                      watch.get(), INFINITE, WT_EXECUTEDEFAULT);
        if (registered == FALSE) {
            winrt::throw_last_error();
        }
        g_watches.push_back(std::move(watch));
        return true;
    });
}

ActionUIWinUIObject *actionUIWinUIRetain(ActionUIWinUIObject *object) {
    if (object != nullptr) {
        reinterpret_cast<::IUnknown *>(object)->AddRef();
    }
    return object;
}

void actionUIWinUIRelease(ActionUIWinUIObject *object) {
    if (object != nullptr) {
        reinterpret_cast<::IUnknown *>(object)->Release();
    }
}

} // extern "C"
