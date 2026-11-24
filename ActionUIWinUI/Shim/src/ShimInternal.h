// ShimInternal.h - what the shim's C++ files share: the WinUI headers, error recording, and the
// conversions between ActionUIWinUIObject and C++/WinRT objects.

#pragma once

#define ACTIONUI_WINUI_SHIM_BUILDING
#include <windows.h>
#include <unknwn.h>
// windows.h defines GetCurrentTime() as a macro, which breaks Storyboard::GetCurrentTime in the
// projection.
#undef GetCurrentTime

#include <chrono>
#include <exception>
#include <functional>
#include <memory>
#include <utility>
#include <string>
#include <string_view>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

#include "ActionUIWinUIShim.h"

namespace actionui_winui {

namespace wf = winrt::Windows::Foundation;
namespace mux = winrt::Microsoft::UI::Xaml;
namespace muxc = winrt::Microsoft::UI::Xaml::Controls;
namespace dispatching = winrt::Microsoft::UI::Dispatching;

// The longest time limit a fetch takes (actionUIWinUIFetchURL, actionUIWinUIFetchURLPrivately), in seconds: 24
// days. A timer's interval may be kept in 32-bit milliseconds (at most about 24.8 days), so a longer one could
// fire early, or at once; a host that wants longer asks for no limit.
constexpr double maximumTimeoutSeconds = 24.0 * 24 * 60 * 60;

// The longest one step of a fetch (sending the request and reading the response's headers, opening the body,
// one read) may wait for the server, whatever the fetch's own time limit: libsoup's on Linux.
constexpr std::chrono::seconds fetchStepLimit{30};

// The calling thread's last error, read by actionUIWinUICopyLastError.
void setLastError(std::string message);

// Record an error for `where` and return false.
bool fail(const char *where, winrt::hresult_error const &error);
bool fail(const char *where, std::exception const &error);
bool fail(const char *where, const char *message);

// Runs body, which returns bool, and turns an exception into a recorded error and false.
template <typename Body>
bool guarded(const char *where, Body &&body) noexcept {
    try {
        return body();
    } catch (winrt::hresult_error const &error) {
        return fail(where, error);
    } catch (std::exception const &error) {
        return fail(where, error);
    } catch (...) {
        return fail(where, "an unknown C++ exception");
    }
}

// Runs body, which returns an ActionUIWinUIObject *, and turns an exception into a recorded error
// and NULL.
template <typename Body>
ActionUIWinUIObject *guardedObject(const char *where, Body &&body) noexcept {
    ActionUIWinUIObject *result = nullptr;
    bool succeeded = guarded(where, [&]() {
        result = body();
        return result != nullptr;
    });
    return succeeded ? result : nullptr;
}

// The calling thread's DispatcherQueue; throws when the thread has none (it is not the UI thread).
dispatching::DispatcherQueue currentQueue();

// Calls callback(context) on `queue`'s thread: at once when this is that thread (or `queue` is
// null), else sent there. When the queue refuses (it is shutting down), the call is dropped: a leak
// rather than a call on the wrong thread.
void callOnUIThread(dispatching::DispatcherQueue const &queue, ActionUIWinUICallback callback, void *context) noexcept;

// What an event registration holds: the caller's handler and context, freed (destroyContext, on
// the UI thread) when the last copy goes, which is when the control lets go of its handlers.
struct EventHandler : std::enable_shared_from_this<EventHandler> {
    EventHandler(ActionUIWinUICallback handler, void *context, ActionUIWinUICallback destroyContext,
                 dispatching::DispatcherQueue queue)
        : handler(handler), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
    EventHandler(EventHandler const &) = delete;
    EventHandler &operator=(EventHandler const &) = delete;
    ~EventHandler() {
        if (destroyContext != nullptr) {
            callOnUIThread(queue, destroyContext, context);
        }
    }
    // Holds the handler alive while it runs: a handler that releases its own control (closing the
    // window) must not free its context under it, whatever XAML does with the delegate meanwhile.
    void fire() const {
        std::shared_ptr<EventHandler const> keep = shared_from_this();
        handler(context);
    }

    ActionUIWinUICallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
    dispatching::DispatcherQueue queue;
};

// Registers an event handler made from `handler`, `context` and `destroyContext` with `connect`,
// which subscribes a lambda holding it to the control's event. destroyContext runs exactly once:
// at once when no holder was made, else when the last copy of the holder goes (the control
// releasing its handlers, or this function returning after a failure).
template <typename Connect>
bool registerHandler(const char *where, ActionUIWinUICallback handler, void *context, ActionUIWinUICallback destroyContext,
                     Connect &&connect) {
    std::shared_ptr<EventHandler> holder;
    bool registered = guarded(where, [&]() {
        if (handler == nullptr) {
            return fail(where, "the handler is NULL");
        }
        holder = std::make_shared<EventHandler>(handler, context, destroyContext, currentQueue());
        connect(holder);
        return true;
    });
    if (!registered && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return registered;
}

// The activation of the windows actionUIWinUIWindowCreate made, by their AppWindow's ID (Window.cpp keeps it from
// each window's Activated event): whether one is the active window, true for a window it does not know (a host's
// own); and the XamlRoot watches of a window whose activation changed (Frames.cpp runs them). UI thread.
bool windowActive(uint64_t windowID);
void windowActivationChanged(uint64_t windowID);

// UTF-8 (NULL reads as empty) to a WinRT string.
winrt::hstring toHString(const char *utf8);

// A new reference to `value`, for the caller to release.
ActionUIWinUIObject *toObject(wf::IInspectable const &value);

// `object` as the WinUI type T (a new reference); throws when it is NULL or not a T.
template <typename T>
T objectAs(ActionUIWinUIObject *object, const wchar_t *typeName) {
    if (object == nullptr) {
        throw winrt::hresult_invalid_argument(L"the object is NULL");
    }
    wf::IInspectable inspectable{nullptr};
    winrt::copy_from_abi(inspectable, object);
    T typed = inspectable.try_as<T>();
    if (typed == nullptr) {
        throw winrt::hresult_no_interface(std::wstring(L"the object is not a ") + typeName);
    }
    return typed;
}

// The outline of SF Symbol `name` as SVG path text (absolute M, L, H, V, Q, C, Z; y down) in a box
// symbolUnits() a side, or nullptr when the shim has none for it (Symbols.cpp).
const char *symbolOutline(const char *name);
double symbolUnits();

// The user's location from Windows' location service (Location.cpp), on the UI thread: each position
// goes to every listener. The service runs while there is a listener; a new one gets the known
// position at once. locationStatus says where it is: "off", "asking Windows", "waiting for a
// position", "running", or why there is no position ("denied: ...", "off: ...", "not available...").
using LocationListener = std::function<void(double latitude, double longitude)>;
int locationListen(LocationListener listener);
void locationStop(int token);
std::string locationStatus();

// The brush for `color`, or for the theme resource `themeBrush`; nullptr for neither (the element's own
// default). Throws when the theme has no such brush. (Styling.cpp)
winrt::Microsoft::UI::Xaml::Media::Brush brushFor(const ActionUIWinUIColor *color, const char *themeBrush);

} // namespace actionui_winui
