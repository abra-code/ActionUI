// Window.cpp - windows, and rendering an element into a PNG file.

#include "ShimInternal.h"

#include <cstdio>
#include <vector>

#include <microsoft.ui.xaml.window.h>  // IWindowNative: the window's HWND

#include <winrt/Windows.UI.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>

namespace actionui_winui {

namespace {

namespace imaging = winrt::Windows::Graphics::Imaging;
namespace streams = winrt::Windows::Storage::Streams;

mux::Window windowFrom(ActionUIWinUIObject *window) {
    return objectAs<mux::Window>(window, L"Window");
}

// What every window's content sits on: a Grid with the theme's page background, as a WinUI page has
// (the brush of the theme in effect when the host is made: a later light/dark switch does not reach
// it yet).
// The background also makes the whole content area render (RenderTargetBitmap draws only what has
// pixels: without it, a window's empty space is cut off).
constexpr wchar_t const *hostName = L"ActionUIWindowHost";

mux::Media::Brush pageBackground() {
    try {
        wf::IInspectable found =
            mux::Application::Current().Resources().Lookup(winrt::box_value(L"ApplicationPageBackgroundThemeBrush"));
        mux::Media::Brush brush = found.try_as<mux::Media::Brush>();
        if (brush != nullptr) {
            return brush;
        }
    } catch (...) {
    }
    return mux::Media::SolidColorBrush(winrt::Windows::UI::Color{255, 255, 255, 255});
}

// The window's host Grid, made and set as its content the first time.
muxc::Grid windowHost(mux::Window const &window) {
    muxc::Grid host = window.Content().try_as<muxc::Grid>();
    if (host != nullptr && host.Name() == hostName) {
        return host;
    }
    host = muxc::Grid();
    host.Name(hostName);
    host.Background(pageBackground());
    window.Content(host);
    return host;
}


// Effective pixels to physical pixels for this window: its monitor's DPI over 96.
double windowScale(mux::Window const &window) {
    HWND hwnd = nullptr;
    winrt::check_hresult(window.as<::IWindowNative>()->get_WindowHandle(&hwnd));
    UINT dpi = GetDpiForWindow(hwnd);
    return dpi != 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
}

void writeFile(std::wstring const &path, std::vector<uint8_t> const &bytes) {
    FILE *file = nullptr;
    errno_t opened = _wfopen_s(&file, path.c_str(), L"wb");
    if (opened != 0 || file == nullptr) {
        throw winrt::hresult_access_denied(L"cannot open the PNG file for writing");
    }
    size_t written = fwrite(bytes.data(), 1, bytes.size(), file);
    int closed = fclose(file);
    if (written != bytes.size() || closed != 0) {
        throw winrt::hresult_error(E_FAIL, L"could not write the whole PNG file");
    }
}

winrt::fire_and_forget renderToPNG(mux::UIElement element, std::wstring path, ActionUIWinUICompletion completion,
                                   void *context) {
    bool succeeded = false;
    try {
        mux::Media::Imaging::RenderTargetBitmap bitmap;
        co_await bitmap.RenderAsync(element);
        streams::IBuffer pixels = co_await bitmap.GetPixelsAsync();
        uint32_t width = static_cast<uint32_t>(bitmap.PixelWidth());
        uint32_t height = static_cast<uint32_t>(bitmap.PixelHeight());
        if (width == 0 || height == 0) {
            throw winrt::hresult_error(E_FAIL, L"the element rendered to an empty bitmap (not laid out yet?)");
        }
        std::vector<uint8_t> bgra(pixels.data(), pixels.data() + pixels.Length());
        double dpi = 96.0;
        mux::XamlRoot root = element.XamlRoot();
        if (root != nullptr) {
            dpi = 96.0 * root.RasterizationScale();
        }

        streams::InMemoryRandomAccessStream stream;
        imaging::BitmapEncoder encoder =
            co_await imaging::BitmapEncoder::CreateAsync(imaging::BitmapEncoder::PngEncoderId(), stream);
        encoder.SetPixelData(imaging::BitmapPixelFormat::Bgra8, imaging::BitmapAlphaMode::Premultiplied, width,
                             height, dpi, dpi, bgra);
        co_await encoder.FlushAsync();

        uint32_t size = static_cast<uint32_t>(stream.Size());
        streams::DataReader reader(stream.GetInputStreamAt(0));
        co_await reader.LoadAsync(size);
        std::vector<uint8_t> png(size);
        reader.ReadBytes(png);
        writeFile(path, png);
        succeeded = true;
    } catch (winrt::hresult_error const &error) {
        fail("render to PNG", error);
    } catch (std::exception const &error) {
        fail("render to PNG", error);
    } catch (...) {
        fail("render to PNG", "an unknown C++ exception");
    }
    if (completion != nullptr) {
        completion(context, succeeded);
    }
}

// Renders `element` into the PNG at `path` from the UI thread's queue, so completion never runs
// before the caller returns.
bool startRender(const char *where, mux::UIElement const &element, const char *path, ActionUIWinUICompletion completion,
                 void *context) {
    if (path == nullptr || path[0] == '\0') {
        return fail(where, "the path is empty");
    }
    if (element.XamlRoot() == nullptr) {
        return fail(where, "the element is not in a window's content");
    }
    std::wstring widePath(toHString(path));
    dispatching::DispatcherQueue queue = dispatching::DispatcherQueue::GetForCurrentThread();
    if (queue == nullptr) {
        return fail(where, "not on the UI thread (no DispatcherQueue)");
    }
    bool queued = queue.TryEnqueue([element, widePath, completion, context]() {
        renderToPNG(element, widePath, completion, context);
    });
    if (!queued) {
        return fail(where, "the UI thread's queue refused the call (shutting down?)");
    }
    return true;
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIWindowCreate(void) {
    return guardedObject("window create", []() {
        mux::Window window;
        return toObject(window);
    });
}

bool actionUIWinUIWindowSetTitle(ActionUIWinUIObject *window, const char *title) {
    return guarded("window set title", [&]() {
        windowFrom(window).Title(toHString(title));
        return true;
    });
}

bool actionUIWinUIWindowSetContentSize(ActionUIWinUIObject *window, double width, double height) {
    return guarded("window set content size", [&]() {
        if (!(width > 0 && height > 0)) {
            return fail("window set content size", "the width and height must be positive");
        }
        mux::Window typed = windowFrom(window);
        double scale = windowScale(typed);
        double physicalWidth = width * scale + 0.5;
        double physicalHeight = height * scale + 0.5;
        // Also refuses infinity: converting an out-of-range double to int32_t is undefined.
        if (!(physicalWidth < 2147483647.0 && physicalHeight < 2147483647.0)) {
            return fail("window set content size", "the width or height is too large");
        }
        typed.AppWindow().ResizeClient(winrt::Windows::Graphics::SizeInt32{static_cast<int32_t>(physicalWidth),
                                                                           static_cast<int32_t>(physicalHeight)});
        return true;
    });
}

bool actionUIWinUIWindowSetContent(ActionUIWinUIObject *window, ActionUIWinUIObject *element) {
    return guarded("window set content", [&]() {
        // Checked before the old content goes: a refused element leaves the window as it was.
        mux::UIElement typed{nullptr};
        if (element != nullptr) {
            typed = objectAs<mux::UIElement>(element, L"UIElement");
        }
        muxc::Grid host = windowHost(windowFrom(window));
        host.Children().Clear();
        if (typed != nullptr) {
            host.Children().Append(typed);
        }
        return true;
    });
}

bool actionUIWinUIWindowRenderToPNG(ActionUIWinUIObject *window, const char *path, ActionUIWinUICompletion completion,
                                    void *context) {
    return guarded("window render to PNG", [&]() {
        mux::Window typed = windowFrom(window);
        if (typed.Content() == nullptr) {
            return fail("window render to PNG", "the window has no content");
        }
        return startRender("window render to PNG", windowHost(typed), path, completion, context);
    });
}

bool actionUIWinUIWindowActivate(ActionUIWinUIObject *window) {
    return guarded("window activate", [&]() {
        windowFrom(window).Activate();
        return true;
    });
}

bool actionUIWinUIWindowClose(ActionUIWinUIObject *window) {
    return guarded("window close", [&]() {
        windowFrom(window).Close();
        return true;
    });
}

bool actionUIWinUIRenderToPNG(ActionUIWinUIObject *element, const char *path, ActionUIWinUICompletion completion,
                              void *context) {
    return guarded("render to PNG", [&]() {
        return startRender("render to PNG", objectAs<mux::UIElement>(element, L"UIElement"), path, completion, context);
    });
}

} // extern "C"
