// ShimInternal.h - what the shim's C++ files share: the WinUI headers, error recording, and the
// conversions between ActionUIWinUIObject and C++/WinRT objects.

#pragma once

#define ACTIONUI_WINUI_SHIM_BUILDING
#include <windows.h>
#include <unknwn.h>
// windows.h defines GetCurrentTime() as a macro, which breaks Storyboard::GetCurrentTime in the
// projection.
#undef GetCurrentTime

#include <exception>
#include <string>
#include <string_view>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>

#include "ActionUIWinUIShim.h"

namespace actionui_winui {

namespace wf = winrt::Windows::Foundation;
namespace mux = winrt::Microsoft::UI::Xaml;
namespace muxc = winrt::Microsoft::UI::Xaml::Controls;
namespace dispatching = winrt::Microsoft::UI::Dispatching;

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

} // namespace actionui_winui
