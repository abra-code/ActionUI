// ShimPrecompiled.h - the system and C++/WinRT headers every shim file includes (through ShimInternal.h),
// compiled once into a precompiled header by Scripts/ci-windows.py: the WinRT projection's headers are most
// of each file's compile time. Nothing of the shim's own goes here, so a change to the shim's headers keeps
// the precompiled header.

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
