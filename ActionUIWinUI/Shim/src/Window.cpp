// Window.cpp - windows, and rendering an element into a PNG file.

#include "ShimInternal.h"

#pragma comment(lib, "dwmapi.lib")

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <limits>
#include <map>
#include <vector>

#include <microsoft.ui.xaml.window.h>  // IWindowNative: the window's HWND
#include <shobjidl_core.h>  // IDataTransferManagerInterop: the share sheet of a desktop app's window
#include <shlobj_core.h>  // SHParseDisplayName, SHOpenFolderAndSelectItems
#include <dwmapi.h>  // DWMWA_CLOAK

#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Content.h>
#include <winrt/Microsoft.UI.Interop.h>  // GetWindowFromWindowId
#include <winrt/Windows.ApplicationModel.DataTransfer.h>

#include <winrt/Windows.UI.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>  // Popup
#include <winrt/Microsoft.UI.Xaml.Input.h>  // Tapped
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Microsoft.Web.WebView2.Core.h>

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

// The window's host Grid, made and set as its content the first time. It holds one Grid, the content
// area, which holds the element and is clipped to its own size, as the window's edge clips it: content
// larger than the window overflows it centered, as in SwiftUI. The clip is on the inner Grid because
// RenderTargetBitmap sizes its picture by everything under the element it renders, ignoring that
// element's own clip: clipped there, the window's PNG would grow by the overflow.
muxc::Grid windowHost(mux::Window const &window) {
    muxc::Grid host = window.Content().try_as<muxc::Grid>();
    if (host != nullptr && host.Name() == hostName) {
        return host;
    }
    host = muxc::Grid();
    host.Name(hostName);
    host.Background(pageBackground());
    muxc::Grid area;
    area.SizeChanged([](wf::IInspectable const &sender, mux::SizeChangedEventArgs const &args) {
        mux::Media::RectangleGeometry clip;
        clip.Rect(wf::Rect{0, 0, args.NewSize().Width, args.NewSize().Height});
        sender.as<mux::UIElement>().Clip(clip);
    });
    host.Children().Append(area);
    window.Content(host);
    return host;
}

// The Grid inside the host that holds the window's element (windowHost).
muxc::Grid windowContentArea(mux::Window const &window) {
    return windowHost(window).Children().GetAt(0).as<muxc::Grid>();
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

// Draws the XAML root's open popups (a dialog, a flyout, a menu) over `bgra`, the rendering of `element`
// at `scale` pixels per effective pixel, at their places: RenderTargetBitmap draws an element's own
// tree, and a popup is in a layer of its own. A popup that cannot be drawn is left out.
winrt::Windows::Foundation::IAsyncAction drawPopups(mux::UIElement element, std::vector<uint8_t> &bgra, uint32_t width,
                                                    uint32_t height, double scale) {
    mux::XamlRoot root = element.XamlRoot();
    if (root == nullptr) {
        co_return;
    }
    auto popups = mux::Media::VisualTreeHelper::GetOpenPopupsForXamlRoot(root);
    // Oldest first, as they are stacked: WinUI lists the newest first (a dialog before the smoke layer
    // it opened under itself).
    for (uint32_t index = popups.Size(); index-- > 0;) {
        mux::UIElement child = popups.GetAt(index).Child();
        if (child == nullptr) {
            continue;
        }
        try {
            // A flyout's presenter renders to nothing (its acrylic background): the first element down
            // its tree that renders stands for it.
            mux::Media::Imaging::RenderTargetBitmap layer;
            streams::IBuffer pixels{nullptr};
            uint32_t layerWidth = 0;
            uint32_t layerHeight = 0;
            for (int depth = 0; depth < 8 && child != nullptr; ++depth) {
                co_await layer.RenderAsync(child);
                pixels = co_await layer.GetPixelsAsync();
                layerWidth = static_cast<uint32_t>(layer.PixelWidth());
                layerHeight = static_cast<uint32_t>(layer.PixelHeight());
                if (layerWidth > 0 && layerHeight > 0) {
                    break;
                }
                child = mux::Media::VisualTreeHelper::GetChildrenCount(child) > 0
                            ? mux::Media::VisualTreeHelper::GetChild(child, 0).try_as<mux::UIElement>()
                            : nullptr;
            }
            if (child == nullptr || pixels == nullptr || pixels.Length() < static_cast<uint64_t>(layerWidth) * layerHeight * 4) {
                continue;
            }
            wf::Point origin = child.TransformToVisual(element).TransformPoint(wf::Point{0, 0});
            int64_t left = std::llround(origin.X * scale);
            int64_t top = std::llround(origin.Y * scale);
            uint8_t const *source = pixels.data();
            // Premultiplied BGRA: the popup over what is under it.
            for (uint32_t y = 0; y < layerHeight; ++y) {
                int64_t row = top + y;
                if (row < 0 || row >= static_cast<int64_t>(height)) {
                    continue;
                }
                for (uint32_t x = 0; x < layerWidth; ++x) {
                    int64_t column = left + x;
                    if (column < 0 || column >= static_cast<int64_t>(width)) {
                        continue;
                    }
                    uint8_t const *from = source + (static_cast<size_t>(y) * layerWidth + x) * 4;
                    uint8_t *to = bgra.data() + (static_cast<size_t>(row) * width + static_cast<size_t>(column)) * 4;
                    uint32_t keep = 255u - from[3];
                    for (int channel = 0; channel < 4; ++channel) {
                        to[channel] = static_cast<uint8_t>(from[channel] + (to[channel] * keep + 127u) / 255u);
                    }
                }
            }
        } catch (winrt::hresult_error const &) {
        }
    }
}

// The part of `element` in which `view` is seen, in `element`'s effective pixels: the view's bounds cut by
// each scroll viewport (a ScrollViewer's content presenter) and rectangular clip between it and `element`.
// The page is drawn there only, as the WebView's own pixels would be.
wf::Rect visibleBounds(muxc::WebView2 const &view, mux::UIElement const &element) {
    auto size = view.ActualSize();
    wf::Rect bounds = view.TransformToVisual(element).TransformBounds(wf::Rect{0, 0, size.x, size.y});
    double left = bounds.X;
    double top = bounds.Y;
    double right = bounds.X + bounds.Width;
    double bottom = bounds.Y + bounds.Height;
    mux::DependencyObject stop = element;
    mux::DependencyObject current = mux::Media::VisualTreeHelper::GetParent(view);
    while (current != nullptr && current != stop) {
        mux::UIElement ancestor = current.try_as<mux::UIElement>();
        if (ancestor != nullptr) {
            mux::Media::RectangleGeometry clip = ancestor.Clip();
            bool cuts = false;
            wf::Rect cut{};
            if (current.try_as<muxc::ScrollContentPresenter>() != nullptr) {
                auto viewport = ancestor.ActualSize();
                cut = wf::Rect{0, 0, viewport.x, viewport.y};
                cuts = true;
            } else if (clip != nullptr) {
                cut = clip.Rect();
                cuts = true;
            }
            if (cuts) {
                wf::Rect within = ancestor.TransformToVisual(element).TransformBounds(cut);
                left = std::max<double>(left, within.X);
                top = std::max<double>(top, within.Y);
                right = std::min<double>(right, within.X + within.Width);
                bottom = std::min<double>(bottom, within.Y + within.Height);
            }
        }
        current = mux::Media::VisualTreeHelper::GetParent(current);
    }
    if (!(right > left && bottom > top)) {
        return wf::Rect{0, 0, 0, 0};
    }
    return wf::Rect{static_cast<float>(left), static_cast<float>(top), static_cast<float>(right - left),
                    static_cast<float>(bottom - top)};
}

// Draws the page of each WebView2 under `element` over `bgra`, the rendering of `element` at `scale` pixels
// per effective pixel, at its place: RenderTargetBitmap leaves a WebView2 blank, as its page is drawn by the
// browser's own process, outside the XAML tree. Each page comes from CoreWebView2.CapturePreviewAsync (what
// the WebView shows now), scaled to the WebView's size. A WebView with no page yet, one that cannot be
// captured, or one whose capture has not come within two seconds (the browser does not draw a page it does
// not show, as in a minimized window, and its capture may never come), is left as it is.
winrt::Windows::Foundation::IAsyncAction drawWebViews(mux::UIElement element, std::vector<uint8_t> &bgra, uint32_t width,
                                                      uint32_t height, double scale) {
    namespace webcore = winrt::Microsoft::Web::WebView2::Core;
    std::vector<muxc::WebView2> views;
    std::vector<mux::DependencyObject> pending{element};
    while (!pending.empty()) {
        mux::DependencyObject current = pending.back();
        pending.pop_back();
        // Nothing under a collapsed element shows (and a hidden WebView's capture may never come).
        mux::UIElement shown = current.try_as<mux::UIElement>();
        if (shown != nullptr && shown.Visibility() != mux::Visibility::Visible) {
            continue;
        }
        if (muxc::WebView2 view = current.try_as<muxc::WebView2>()) {
            views.push_back(view);
            continue;
        }
        int32_t count = mux::Media::VisualTreeHelper::GetChildrenCount(current);
        for (int32_t index = 0; index < count; ++index) {
            pending.push_back(mux::Media::VisualTreeHelper::GetChild(current, index));
        }
    }
    winrt::apartment_context uiThread;
    for (muxc::WebView2 const &view : views) {
        try {
            webcore::CoreWebView2 core = view.CoreWebView2();
            auto size = view.ActualSize();
            if (core == nullptr || !(size.x > 0 && size.y > 0)) {
                continue;
            }
            // Where the view is now, as in the rendering just taken; in pixels of `bgra`, the visible part
            // cut to the image.
            wf::Point origin = view.TransformToVisual(element).TransformPoint(wf::Point{0, 0});
            int64_t left = std::llround(origin.X * scale);
            int64_t top = std::llround(origin.Y * scale);
            wf::Rect visible = visibleBounds(view, element);
            int64_t fromColumn = std::max<int64_t>(0, std::llround(visible.X * scale));
            int64_t fromRow = std::max<int64_t>(0, std::llround(visible.Y * scale));
            int64_t toColumn = std::min<int64_t>(width, std::llround((visible.X + visible.Width) * scale));
            int64_t toRow = std::min<int64_t>(height, std::llround((visible.Y + visible.Height) * scale));
            if (toColumn <= fromColumn || toRow <= fromRow) {
                continue;
            }
            streams::InMemoryRandomAccessStream captured;
            wf::IAsyncAction capture =
                core.CapturePreviewAsync(webcore::CoreWebView2CapturePreviewImageFormat::Png, captured);
            auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
            while (capture.Status() == wf::AsyncStatus::Started && std::chrono::steady_clock::now() < deadline) {
                co_await winrt::resume_after(std::chrono::milliseconds(20));
                co_await uiThread;
            }
            if (capture.Status() == wf::AsyncStatus::Started) {
                continue;
            }
            // Throws the capture's error, if it failed.
            capture.GetResults();
            captured.Seek(0);
            imaging::BitmapDecoder decoder = co_await imaging::BitmapDecoder::CreateAsync(captured);
            uint32_t pageWidth = static_cast<uint32_t>(std::max<int64_t>(1, std::llround(size.x * scale)));
            uint32_t pageHeight = static_cast<uint32_t>(std::max<int64_t>(1, std::llround(size.y * scale)));
            imaging::BitmapTransform transform;
            transform.ScaledWidth(pageWidth);
            transform.ScaledHeight(pageHeight);
            transform.InterpolationMode(imaging::BitmapInterpolationMode::Fant);
            imaging::PixelDataProvider data = co_await decoder.GetPixelDataAsync(
                imaging::BitmapPixelFormat::Bgra8, imaging::BitmapAlphaMode::Premultiplied, transform,
                imaging::ExifOrientationMode::IgnoreExifOrientation, imaging::ColorManagementMode::DoNotColorManage);
            winrt::com_array<uint8_t> pixels = data.DetachPixelData();
            if (pixels.size() < static_cast<size_t>(pageWidth) * pageHeight * 4) {
                continue;
            }
            // Premultiplied BGRA: the page over what is under it, where the view is seen.
            for (uint32_t y = 0; y < pageHeight; ++y) {
                int64_t row = top + y;
                if (row < fromRow || row >= toRow) {
                    continue;
                }
                for (uint32_t x = 0; x < pageWidth; ++x) {
                    int64_t column = left + x;
                    if (column < fromColumn || column >= toColumn) {
                        continue;
                    }
                    uint8_t const *from = pixels.data() + (static_cast<size_t>(y) * pageWidth + x) * 4;
                    uint8_t *to = bgra.data() + (static_cast<size_t>(row) * width + static_cast<size_t>(column)) * 4;
                    uint32_t keep = 255u - from[3];
                    for (int channel = 0; channel < 4; ++channel) {
                        to[channel] = static_cast<uint8_t>(from[channel] + (to[channel] * keep + 127u) / 255u);
                    }
                }
            }
        } catch (winrt::hresult_error const &) {
        }
    }
}

winrt::fire_and_forget renderToPNG(mux::UIElement element, std::wstring path, ActionUIWinUICompletion completion,
                                   void *context, bool withPopups, uint32_t maxPixels) {
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
        if (withPopups && bgra.size() >= static_cast<size_t>(width) * height * 4) {
            float elementWidth = element.ActualSize().x;
            double scale = elementWidth > 0 ? width / elementWidth : 1.0;
            // The pages first: a popup shows over them.
            co_await drawWebViews(element, bgra, width, height, scale);
            co_await drawPopups(element, bgra, width, height, scale);
        }
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
        // No larger than maxPixels on its longest side (0: no cap): scaled as it is encoded.
        uint32_t longest = std::max(width, height);
        if (maxPixels > 0 && longest > maxPixels) {
            double factor = static_cast<double>(maxPixels) / longest;
            encoder.BitmapTransform().ScaledWidth(std::max<uint32_t>(1, static_cast<uint32_t>(width * factor + 0.5)));
            encoder.BitmapTransform().ScaledHeight(std::max<uint32_t>(1, static_cast<uint32_t>(height * factor + 0.5)));
            encoder.BitmapTransform().InterpolationMode(imaging::BitmapInterpolationMode::Fant);
        }
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
                 void *context, bool withPopups = false, uint32_t maxPixels = 0) {
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
    bool queued = queue.TryEnqueue([element, widePath, completion, context, withPopups, maxPixels]() {
        renderToPNG(element, widePath, completion, context, withPopups, maxPixels);
    });
    if (!queued) {
        return fail(where, "the UI thread's queue refused the call (shutting down?)");
    }
    return true;
}

// What a test's real pointer input needs (actionUIWinUIWindowSendDrag, actionUIWinUIWindowSendWheel):
// `element`'s points as SendInput's absolute mouse input, with `window` brought to the front so the
// input goes to it. False (the error set, as fail sets it) when that cannot be done.
bool realPointerInput(const char *where, ActionUIWinUIObject *window, ActionUIWinUIObject *element,
                      std::function<INPUT(double, double, DWORD)> &inputAt) {
    mux::Window typed = windowFrom(window);
    mux::UIElement target = objectAs<mux::UIElement>(element, L"UIElement");
    mux::UIElement content = typed.Content();
    if (content == nullptr || target.XamlRoot() == nullptr || target.XamlRoot() != content.XamlRoot()) {
        return fail(where, "the element is not shown in the window");
    }
    HWND hwnd = nullptr;
    winrt::check_hresult(typed.as<::IWindowNative>()->get_WindowHandle(&hwnd));
    // The element's points in the window's content (its client area), then in physical pixels on
    // the screen: SendInput takes the whole desktop as 0 to 65535 each way.
    mux::Media::GeneralTransform transform = target.TransformToVisual(nullptr);
    double scale = windowScale(typed);
    int left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (width <= 1 || height <= 1) {
        return fail(where, "no desktop to send the pointer's input to");
    }
    // Input goes to the desktop the user sees: a program on another one (a service's) has none to send.
    HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    if (input == nullptr) {
        return fail(where, "no access to the desktop that takes the mouse's input (not an interactive session?)");
    }
    CloseDesktop(input);
    // In front, so the pointer's input goes to it. Windows lets only the program the user last worked
    // with bring a window to the front (a test runner's may be another): sharing the front window's
    // input state for a moment lets this one.
    SetForegroundWindow(hwnd);
    if (GetForegroundWindow() != hwnd) {
        HWND front = GetForegroundWindow();
        DWORD frontThread = front != nullptr ? GetWindowThreadProcessId(front, nullptr) : 0;
        DWORD ownThread = GetCurrentThreadId();
        bool attached = frontThread != 0 && frontThread != ownThread && AttachThreadInput(ownThread, frontThread, TRUE);
        BringWindowToTop(hwnd);
        SetForegroundWindow(hwnd);
        if (attached) {
            AttachThreadInput(ownThread, frontThread, FALSE);
        }
    }
    if (GetForegroundWindow() != hwnd) {
        wchar_t name[128] = L"";
        HWND front = GetForegroundWindow();
        if (front == nullptr || GetClassNameW(front, name, 128) == 0) {
            wcscpy_s(name, L"none");
        }
        std::string message = "Windows did not bring the window to the front (in front: " + winrt::to_string(name) + ")";
        return fail(where, message.c_str());
    }
    inputAt = [hwnd, transform, scale, left, top, width, height](double x, double y, DWORD flags) {
        wf::Point point = transform.TransformPoint(wf::Point{static_cast<float>(x), static_cast<float>(y)});
        POINT pixel{static_cast<LONG>(std::lround(point.X * scale)), static_cast<LONG>(std::lround(point.Y * scale))};
        if (!ClientToScreen(hwnd, &pixel)) {
            throw winrt::hresult_error(E_FAIL, L"the window's position on the screen is unknown");
        }
        INPUT input{};
        input.type = INPUT_MOUSE;
        // Rounded up: the pixel itself whether Windows maps back by truncating or by rounding.
        input.mi.dx = static_cast<LONG>(std::min(std::ceil((pixel.x - left) * 65536.0 / width), 65535.0));
        input.mi.dy = static_cast<LONG>(std::min(std::ceil((pixel.y - top) * 65536.0 / height), 65535.0));
        input.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK | flags;
        return input;
    };
    return true;
}

// Sends `batches` through Windows' input queue, each 15 ms after the one before, as a hand moves (Windows
// stamps each with the time it is sent). When Windows takes only part of one, `undo` (if any) is sent
// after a first batch went through (a button left down is let up), and this fails.
bool sendInputBatches(const char *where, std::vector<std::vector<INPUT>> &batches, INPUT const *undo) {
    for (size_t index = 0; index < batches.size(); index++) {
        if (index > 0) {
            Sleep(15);
        }
        std::vector<INPUT> &inputs = batches[index];
        // Cleared first: SendInput does not always set it, and an earlier call's error would be reported.
        ::SetLastError(0);
        UINT sent = SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
        if (sent != inputs.size()) {
            DWORD error = GetLastError();
            if (index > 0 && undo != nullptr) {
                INPUT again = *undo;
                SendInput(1, &again, sizeof(INPUT));
            }
            if (error != 0) {
                throw winrt::hresult_error(HRESULT_FROM_WIN32(error));
            }
            return fail(where, "Windows took only part of the pointer's input (another program's input in the way?)");
        }
    }
    return true;
}

// Whether each window actionUIWinUIWindowCreate made is active, by its AppWindow's ID. UI thread.
std::map<uint64_t, bool> &windowActivation() {
    static std::map<uint64_t, bool> states;
    return states;
}

} // namespace

bool windowActive(uint64_t windowID) {
    auto found = windowActivation().find(windowID);
    return found == windowActivation().end() || found->second;
}

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIWindowCreate(void) {
    return guardedObject("window create", []() {
        mux::Window window;
        // Its activation, for the elements in it that follow it (a HostSurface's keyboard focus).
        uint64_t windowID = window.AppWindow().Id().Value;
        windowActivation()[windowID] = false;
        window.Activated([windowID](auto &&, mux::WindowActivatedEventArgs const &arguments) {
            guarded("window activated", [&]() {
                // Not after Closed: an entry made again would outlive the window, and its ID may be reused.
                auto found = windowActivation().find(windowID);
                if (found == windowActivation().end()) {
                    return true;
                }
                found->second = arguments.WindowActivationState() != mux::WindowActivationState::Deactivated;
                windowActivationChanged(windowID);
                return true;
            });
        });
        window.Closed([windowID](auto &&, auto &&) {
            windowActivation().erase(windowID);
        });
        return toObject(window);
    });
}

ActionUIWinUIObject *actionUIWinUIWindowFromInspectable(void *inspectable) {
    return guardedObject("window from inspectable", [&]() -> ActionUIWinUIObject * {
        if (inspectable == nullptr) {
            fail("window from inspectable", "the window is NULL");
            return nullptr;
        }
        wf::IInspectable object{nullptr};
        winrt::copy_from_abi(object, inspectable);
        mux::Window window = object.try_as<mux::Window>();
        if (window == nullptr) {
            fail("window from inspectable", "the object is no Microsoft.UI.Xaml.Window");
            return nullptr;
        }
        return toObject(window);
    });
}

bool actionUIWinUIWindowSetTitle(ActionUIWinUIObject *window, const char *title) {
    return guarded("window set title", [&]() {
        windowFrom(window).Title(toHString(title));
        return true;
    });
}

bool actionUIWinUIWindowSetResizable(ActionUIWinUIObject *window, bool resizable) {
    return guarded("window set resizable", [&]() {
        winrt::Microsoft::UI::Windowing::OverlappedPresenter presenter =
            windowFrom(window).AppWindow().Presenter().try_as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
        if (presenter == nullptr) {
            return fail("window set resizable", "the window has no overlapped presenter");
        }
        presenter.IsResizable(resizable);
        presenter.IsMaximizable(resizable);
        return true;
    });
}

bool actionUIWinUIWindowSetMinimumContentSize(ActionUIWinUIObject *window, double width, double height) {
    return guarded("window set minimum content size", [&]() {
        if (!(width >= 0 && width < 1000000.0 && height >= 0 && height < 1000000.0)) {
            return fail("window set minimum content size", "the width and height must be 0 or more, and finite");
        }
        mux::Window typed = windowFrom(window);
        winrt::Microsoft::UI::Windowing::AppWindow appWindow = typed.AppWindow();
        winrt::Microsoft::UI::Windowing::OverlappedPresenter presenter =
            appWindow.Presenter().try_as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
        if (presenter == nullptr) {
            return fail("window set minimum content size", "the window has no overlapped presenter");
        }
        // The presenter's minimum is the whole window's, in physical pixels: the content's size at the window's
        // scale plus its frame (and title bar, down).
        double scale = windowScale(typed);
        int32_t frameWidth = appWindow.Size().Width - appWindow.ClientSize().Width;
        int32_t frameHeight = appWindow.Size().Height - appWindow.ClientSize().Height;
        if (width == 0) {
            presenter.PreferredMinimumWidth(nullptr);
        } else {
            presenter.PreferredMinimumWidth(static_cast<int32_t>(width * scale + 0.5) + (frameWidth > 0 ? frameWidth : 0));
        }
        if (height == 0) {
            presenter.PreferredMinimumHeight(nullptr);
        } else {
            presenter.PreferredMinimumHeight(static_cast<int32_t>(height * scale + 0.5) + (frameHeight > 0 ? frameHeight : 0));
        }
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
        winrt::Microsoft::UI::Windowing::AppWindow appWindow = typed.AppWindow();
        winrt::Windows::Graphics::SizeInt32 wanted{static_cast<int32_t>(physicalWidth), static_cast<int32_t>(physicalHeight)};
        appWindow.ResizeClient(wanted);
        // ResizeClient counts a title bar a window without one (a notice) does not have: its content area
        // came out that much taller. Corrected from what the window reports, for a restored window still at
        // the scale it was sized at: a minimized one reports no content area, and one the resize took to a
        // monitor of another scale was sized again by Windows for that scale.
        auto presenter = appWindow.Presenter().try_as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
        bool restored = presenter != nullptr &&
                        presenter.State() == winrt::Microsoft::UI::Windowing::OverlappedPresenterState::Restored;
        winrt::Windows::Graphics::SizeInt32 got = appWindow.ClientSize();
        if (restored && windowScale(typed) == scale && (got.Width != wanted.Width || got.Height != wanted.Height)) {
            winrt::Windows::Graphics::SizeInt32 outer = appWindow.Size();
            appWindow.Resize(winrt::Windows::Graphics::SizeInt32{outer.Width + wanted.Width - got.Width,
                                                                 outer.Height + wanted.Height - got.Height});
        }
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
        muxc::Grid area = windowContentArea(windowFrom(window));
        area.Children().Clear();
        if (typed != nullptr) {
            area.Children().Append(typed);
        }
        return true;
    });
}

namespace {

// The host's rows, made the first time a bar is set: the menu bar (Auto), the top bar (Auto), the
// content area (Star). The content area stays the host's first child (windowContentArea); a bar is
// found by its row.
void ensureBarRows(muxc::Grid const &host) {
    if (host.RowDefinitions().Size() != 0) {
        return;
    }
    for (int row = 0; row < 2; ++row) {
        muxc::RowDefinition barRow;
        barRow.Height(mux::GridLength{0, mux::GridUnitType::Auto});
        host.RowDefinitions().Append(barRow);
    }
    muxc::RowDefinition contentRow;
    contentRow.Height(mux::GridLength{1, mux::GridUnitType::Star});
    host.RowDefinitions().Append(contentRow);
    muxc::Grid::SetRow(host.Children().GetAt(0).as<mux::FrameworkElement>(), 2);
}

// Puts `bar` (nullptr: none) in the host's row `row`, in place of the one there.
void setBar(muxc::Grid const &host, int32_t row, mux::FrameworkElement const &bar) {
    if (bar == nullptr && host.RowDefinitions().Size() == 0) {
        return;  // never had a bar: the window's layout stays as it was
    }
    ensureBarRows(host);
    for (uint32_t index = host.Children().Size(); index > 1; --index) {
        auto child = host.Children().GetAt(index - 1).try_as<mux::FrameworkElement>();
        if (child != nullptr && muxc::Grid::GetRow(child) == row) {
            host.Children().RemoveAt(index - 1);
        }
    }
    if (bar != nullptr) {
        muxc::Grid::SetRow(bar, row);
        host.Children().Append(bar);
    }
}

// The height `element` asks for with unbounded room.
double desiredHeight(mux::UIElement const &element) {
    element.Measure(wf::Size{std::numeric_limits<float>::infinity(), std::numeric_limits<float>::infinity()});
    return element.DesiredSize().Height;
}

} // namespace

bool actionUIWinUIWindowSetMenuBar(ActionUIWinUIObject *window, ActionUIWinUIObject *menuBar) {
    return guarded("window set menu bar", [&]() {
        // Checked before anything changes: a refused object leaves the window as it was.
        muxc::MenuBar bar{nullptr};
        if (menuBar != nullptr) {
            bar = objectAs<muxc::MenuBar>(menuBar, L"MenuBar");
        }
        setBar(windowHost(windowFrom(window)), 0, bar);
        return true;
    });
}

bool actionUIWinUIWindowSetTopBar(ActionUIWinUIObject *window, ActionUIWinUIObject *topBar) {
    return guarded("window set top bar", [&]() {
        mux::FrameworkElement bar{nullptr};
        if (topBar != nullptr) {
            bar = objectAs<mux::FrameworkElement>(topBar, L"FrameworkElement");
        }
        setBar(windowHost(windowFrom(window)), 1, bar);
        return true;
    });
}

double actionUIWinUIWindowMenuBarHeight(ActionUIWinUIObject *window) {
    double height = -1;
    guarded("window menu bar height", [&]() {
        height = 0;
        muxc::Grid host = windowHost(windowFrom(window));
        for (uint32_t index = 1; index < host.Children().Size(); ++index) {
            auto child = host.Children().GetAt(index).as<mux::FrameworkElement>();
            if (muxc::Grid::GetRow(child) == 0) {
                height = desiredHeight(child);
            }
        }
        return true;
    });
    return height;
}

double actionUIWinUIWindowHeightAboveContent(ActionUIWinUIObject *window) {
    double height = -1;
    guarded("window height above content", [&]() {
        height = 0;
        muxc::Grid host = windowHost(windowFrom(window));
        for (uint32_t index = 1; index < host.Children().Size(); ++index) {
            height += desiredHeight(host.Children().GetAt(index));
        }
        return true;
    });
    return height;
}

bool actionUIWinUIWindowRenderToPNG(ActionUIWinUIObject *window, const char *path, ActionUIWinUICompletion completion,
                                    void *context) {
    return guarded("window render to PNG", [&]() {
        mux::Window typed = windowFrom(window);
        if (typed.Content() == nullptr) {
            return fail("window render to PNG", "the window has no content");
        }
        // With what the window shows over its content: a dialog, a flyout, an open menu.
        return startRender("window render to PNG", windowHost(typed), path, completion, context, true);
    });
}

bool actionUIWinUIWindowRenderToPNGWithin(ActionUIWinUIObject *window, const char *path, uint32_t maxPixels,
                                          ActionUIWinUICompletion completion, void *context) {
    return guarded("window render to PNG within", [&]() {
        mux::Window typed = windowFrom(window);
        if (typed.Content() == nullptr) {
            return fail("window render to PNG within", "the window has no content");
        }
        return startRender("window render to PNG within", windowHost(typed), path, completion, context, true, maxPixels);
    });
}

bool actionUIWinUIWindowRenderContentToPNG(ActionUIWinUIObject *window, const char *path, ActionUIWinUICompletion completion,
                                           void *context) {
    return guarded("window render content to PNG", [&]() {
        mux::Window typed = windowFrom(window);
        if (typed.Content() == nullptr) {
            return fail("window render content to PNG", "the window has no content");
        }
        // The content area alone: no menu bar or top bar, and nothing open over it.
        return startRender("window render content to PNG", windowContentArea(typed), path, completion, context);
    });
}

bool actionUIWinUIClipboardSetText(const char *text) {
    return guarded("clipboard set text", [&]() {
        winrt::Windows::ApplicationModel::DataTransfer::DataPackage package;
        package.SetText(toHString(text));
        winrt::Windows::ApplicationModel::DataTransfer::Clipboard::SetContent(package);
        winrt::Windows::ApplicationModel::DataTransfer::Clipboard::Flush();
        return true;
    });
}

bool actionUIWinUIRevealInFileExplorer(const char *path) {
    return guarded("reveal in File Explorer", [&]() {
        if (path == nullptr || path[0] == '\0') {
            return fail("reveal in File Explorer", "the path is empty");
        }
        std::wstring wide(toHString(path));
        // The file selected in its folder's window; the file itself is not opened.
        PIDLIST_ABSOLUTE item = nullptr;
        HRESULT parsed = SHParseDisplayName(wide.c_str(), nullptr, &item, 0, nullptr);
        if (FAILED(parsed) || item == nullptr) {
            return fail("reveal in File Explorer", "the path names nothing the shell knows");
        }
        HRESULT shown = SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
        CoTaskMemFree(item);
        if (FAILED(shown)) {
            return fail("reveal in File Explorer", "File Explorer did not show it");
        }
        return true;
    });
}

bool actionUIWinUIWindowActivate(ActionUIWinUIObject *window) {
    return guarded("window activate", [&]() {
        mux::Window shown = windowFrom(window);
        // A minimized window is restored first, so bringing it to the front also shows it.
        auto presenter = shown.AppWindow().Presenter().try_as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
        if (presenter != nullptr &&
            presenter.State() == winrt::Microsoft::UI::Windowing::OverlappedPresenterState::Minimized) {
            presenter.Restore();
        }
        shown.Activate();
        return true;
    });
}

bool actionUIWinUIWindowPlaceOffscreen(ActionUIWinUIObject *window) {
    return guarded("window place offscreen", [&]() {
        winrt::Microsoft::UI::Windowing::AppWindow appWindow = windowFrom(window).AppWindow();
        appWindow.IsShownInSwitchers(false);
        // Past the right and bottom edges of the rectangle around all monitors.
        int32_t right = GetSystemMetrics(SM_XVIRTUALSCREEN) + GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int32_t bottom = GetSystemMetrics(SM_YVIRTUALSCREEN) + GetSystemMetrics(SM_CYVIRTUALSCREEN);
        appWindow.Move(winrt::Windows::Graphics::PointInt32{right + 100, bottom + 100});
        return true;
    });
}

bool actionUIWinUIWindowSetCloaked(ActionUIWinUIObject *window, bool cloaked) {
    return guarded("window set cloaked", [&]() {
        HWND hwnd = nullptr;
        winrt::check_hresult(windowFrom(window).as<::IWindowNative>()->get_WindowHandle(&hwnd));
        BOOL value = cloaked ? TRUE : FALSE;
        winrt::check_hresult(DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, &value, static_cast<DWORD>(sizeof(value))));
        return true;
    });
}

bool actionUIWinUIWindowMakeNotice(ActionUIWinUIObject *window) {
    return guarded("window make notice", [&]() {
        mux::Window typed = windowFrom(window);
        winrt::Microsoft::UI::Windowing::AppWindow appWindow = typed.AppWindow();
        auto presenter = appWindow.Presenter().as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
        // The thin border keeps Windows 11's rounded corners and shadow; no title bar, no resizing.
        presenter.SetBorderAndTitleBar(true, false);
        presenter.IsResizable(false);
        presenter.IsMaximizable(false);
        presenter.IsMinimizable(false);
        presenter.IsAlwaysOnTop(true);
        appWindow.IsShownInSwitchers(false);
        // Acrylic, as Windows' own notifications: the host's page background would hide it.
        typed.SystemBackdrop(mux::Media::DesktopAcrylicBackdrop());
        windowHost(typed).Background(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
        return true;
    });
}

bool actionUIWinUIWindowFrame(ActionUIWinUIObject *window, int32_t *x, int32_t *y, int32_t *width, int32_t *height) {
    return guarded("window frame", [&]() {
        if (x == nullptr || y == nullptr || width == nullptr || height == nullptr) {
            return fail("window frame", "a pointer is NULL");
        }
        winrt::Microsoft::UI::Windowing::AppWindow appWindow = windowFrom(window).AppWindow();
        auto position = appWindow.Position();
        auto size = appWindow.Size();
        *x = position.X;
        *y = position.Y;
        *width = size.Width;
        *height = size.Height;
        return true;
    });
}

bool actionUIWinUIWindowWorkArea(ActionUIWinUIObject *window, int32_t *x, int32_t *y, int32_t *width, int32_t *height) {
    return guarded("window work area", [&]() {
        if (x == nullptr || y == nullptr || width == nullptr || height == nullptr) {
            return fail("window work area", "a pointer is NULL");
        }
        auto area = winrt::Microsoft::UI::Windowing::DisplayArea::GetFromWindowId(
            windowFrom(window).AppWindow().Id(), winrt::Microsoft::UI::Windowing::DisplayAreaFallback::Primary);
        if (area == nullptr) {
            return fail("window work area", "no display");
        }
        auto work = area.WorkArea();
        *x = work.X;
        *y = work.Y;
        *width = work.Width;
        *height = work.Height;
        return true;
    });
}

bool actionUIWinUIWindowMove(ActionUIWinUIObject *window, int32_t x, int32_t y) {
    return guarded("window move", [&]() {
        windowFrom(window).AppWindow().Move(winrt::Windows::Graphics::PointInt32{x, y});
        return true;
    });
}

bool actionUIWinUIWindowShowInactive(ActionUIWinUIObject *window) {
    return guarded("window show inactive", [&]() {
        windowFrom(window).AppWindow().Show(false);
        return true;
    });
}

bool actionUIWinUIWindowContentSize(ActionUIWinUIObject *window, double *width, double *height) {
    return guarded("window content size", [&]() {
        if (width == nullptr || height == nullptr) {
            return fail("window content size", "the width or height pointer is NULL");
        }
        auto size = windowContentArea(windowFrom(window)).ActualSize();
        *width = size.x;
        *height = size.y;
        return true;
    });
}

bool actionUIWinUIWindowPosition(ActionUIWinUIObject *window, int32_t *x, int32_t *y) {
    return guarded("window position", [&]() {
        if (x == nullptr || y == nullptr) {
            return fail("window position", "the x or y pointer is NULL");
        }
        auto position = windowFrom(window).AppWindow().Position();
        *x = position.X;
        *y = position.Y;
        return true;
    });
}

bool actionUIWinUIWindowMoveOnScreen(ActionUIWinUIObject *window, int32_t x, int32_t y, bool *moved) {
    return guarded("window move on screen", [&]() {
        if (moved == nullptr) {
            return fail("window move on screen", "the moved pointer is NULL");
        }
        *moved = false;
        // A point in the title bar near its left end, where the user can take hold of the window: past the
        // frame's invisible resize border and the title bar's top edge. In 64 bits: x or y may be near the
        // end of int32_t's range.
        int64_t probeX = static_cast<int64_t>(x) + 64;
        int64_t probeY = static_cast<int64_t>(y) + 16;
        if (probeX > INT32_MAX || probeY > INT32_MAX) {
            return true;
        }
        POINT probe{static_cast<LONG>(probeX), static_cast<LONG>(probeY)};
        if (MonitorFromPoint(probe, MONITOR_DEFAULTTONULL) == nullptr) {
            return true;
        }
        windowFrom(window).AppWindow().Move(winrt::Windows::Graphics::PointInt32{x, y});
        *moved = true;
        return true;
    });
}

bool actionUIWinUIWindowIsActive(ActionUIWinUIObject *window) {
    try {
        HWND hwnd = nullptr;
        winrt::check_hresult(windowFrom(window).as<::IWindowNative>()->get_WindowHandle(&hwnd));
        return hwnd != nullptr && GetActiveWindow() == hwnd;
    } catch (...) {
        return false;
    }
}

bool actionUIWinUIWindowSendDrag(ActionUIWinUIObject *window, ActionUIWinUIObject *element, double fromX, double fromY,
                                 double toX, double toY) {
    return guarded("window send drag", [&]() {
        if (!std::isfinite(fromX) || !std::isfinite(fromY) || !std::isfinite(toX) || !std::isfinite(toY)) {
            return fail("window send drag", "a point is not finite");
        }
        std::function<INPUT(double, double, DWORD)> inputAt;
        if (!realPointerInput("window send drag", window, element, inputAt)) {
            return false;
        }
        // Pressed at the start, moved there in steps, released at the end, each step sent apart from
        // the one before as a hand moves: sent at once, the drag would read as a flick far faster than
        // a hand's, and a map would glide away.
        std::vector<std::vector<INPUT>> batches;
        batches.push_back({inputAt(fromX, fromY, 0), inputAt(fromX, fromY, MOUSEEVENTF_LEFTDOWN)});
        constexpr int steps = 8;
        for (int step = 1; step <= steps; step++) {
            double fraction = static_cast<double>(step) / steps;
            batches.push_back({inputAt(fromX + (toX - fromX) * fraction, fromY + (toY - fromY) * fraction, 0)});
        }
        INPUT up = inputAt(toX, toY, MOUSEEVENTF_LEFTUP);
        batches.push_back({up});
        // The button is not left down.
        return sendInputBatches("window send drag", batches, &up);
    });
}

bool actionUIWinUIWindowSendWheel(ActionUIWinUIObject *window, ActionUIWinUIObject *element, double x, double y,
                                  double notchesX, double notchesY) {
    return guarded("window send wheel", [&]() {
        if (!std::isfinite(x) || !std::isfinite(y)) {
            return fail("window send wheel", "the point is not finite");
        }
        if (!(std::fabs(notchesX) <= 100) || !(std::fabs(notchesY) <= 100)) {
            return fail("window send wheel", "a turn is not finite or more than 100 notches");
        }
        std::function<INPUT(double, double, DWORD)> inputAt;
        if (!realPointerInput("window send wheel", window, element, inputAt)) {
            return false;
        }
        // The wheel turns where the pointer is: moved there first, as a hand moves before it scrolls.
        std::vector<std::vector<INPUT>> batches;
        batches.push_back({inputAt(x, y, 0)});
        // A notch is WHEEL_DELTA; Windows counts a turn away from the user (toward the top) as positive,
        // and a tilt toward the right.
        if (notchesY != 0) {
            INPUT wheel{};
            wheel.type = INPUT_MOUSE;
            wheel.mi.dwFlags = MOUSEEVENTF_WHEEL;
            wheel.mi.mouseData = static_cast<DWORD>(static_cast<LONG>(std::lround(-notchesY * WHEEL_DELTA)));
            batches.push_back({wheel});
        }
        if (notchesX != 0) {
            INPUT tilt{};
            tilt.type = INPUT_MOUSE;
            tilt.mi.dwFlags = MOUSEEVENTF_HWHEEL;
            tilt.mi.mouseData = static_cast<DWORD>(static_cast<LONG>(std::lround(notchesX * WHEEL_DELTA)));
            batches.push_back({tilt});
        }
        return sendInputBatches("window send wheel", batches, nullptr);
    });
}

bool actionUIWinUIShareLink(ActionUIWinUIObject *element, const char *url, const char *title, const char *text) {
    return guarded("share link", [&]() {
        namespace transfer = winrt::Windows::ApplicationModel::DataTransfer;
        mux::UIElement target = objectAs<mux::UIElement>(element, L"UIElement");
        if (url == nullptr || title == nullptr) {
            return fail("share link", "no URL or title to share");
        }
        // Not absolute ("example.com"): shared as text alone.
        wf::Uri link{nullptr};
        try {
            link = wf::Uri(toHString(url));
        } catch (winrt::hresult_error const &) {
            link = nullptr;
        }
        mux::XamlRoot root = target.XamlRoot();
        if (root == nullptr) {
            return fail("share link", "the element is in no window");
        }
        winrt::Microsoft::UI::Content::ContentIslandEnvironment environment = root.ContentIslandEnvironment();
        if (environment == nullptr) {
            return fail("share link", "the element's window is not known");
        }
        HWND hwnd = winrt::Microsoft::UI::GetWindowFromWindowId(environment.AppWindowId());
        if (hwnd == nullptr) {
            return fail("share link", "the element's window has no handle");
        }
        auto interop = winrt::get_activation_factory<transfer::DataTransferManager, IDataTransferManagerInterop>();
        transfer::DataTransferManager manager{nullptr};
        winrt::check_hresult(interop->GetForWindow(hwnd, winrt::guid_of<transfer::DataTransferManager>(), winrt::put_abi(manager)));
        // The sheet asks for the data as it opens: this request's, then the handler goes.
        winrt::hstring shownTitle = toHString(title);
        winrt::hstring shownText = toHString(text);
        auto token = std::make_shared<winrt::event_token>();
        *token = manager.DataRequested([link, shownTitle, shownText, token](transfer::DataTransferManager const &sender,
                                                                            transfer::DataRequestedEventArgs const &args) {
            sender.DataRequested(*token);
            transfer::DataPackage data = args.Request().Data();
            // The sheet refuses a package without a title.
            data.Properties().Title(shownTitle);
            if (link != nullptr) {
                data.SetWebLink(link);
            }
            if (!shownText.empty()) {
                data.SetText(shownText);
            }
        });
        HRESULT shown = interop->ShowShareUIForWindow(hwnd);
        if (FAILED(shown)) {
            manager.DataRequested(*token);
            winrt::check_hresult(shown);
        }
        return true;
    });
}

bool actionUIWinUIWindowClose(ActionUIWinUIObject *window) {
    return guarded("window close", [&]() {
        windowFrom(window).Close();
        return true;
    });
}

bool actionUIWinUIWindowOnClosed(ActionUIWinUIObject *window, ActionUIWinUICallback handler, void *context,
                                 ActionUIWinUICallback destroyContext) {
    return registerHandler("window on closed", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        windowFrom(window).Closed([holder](auto &&, auto &&) { holder->fire(); });
    });
}

bool actionUIWinUIWindowOnTapped(ActionUIWinUIObject *window, ActionUIWinUICallback handler, void *context,
                                 ActionUIWinUICallback destroyContext) {
    return registerHandler("window on tapped", handler, context, destroyContext, [&](std::shared_ptr<EventHandler> const &holder) {
        windowHost(windowFrom(window)).Tapped([holder](auto &&, auto &&) { holder->fire(); });
    });
}

bool actionUIWinUIWindowOnClosing(ActionUIWinUIObject *window, ActionUIWinUIWindowCloseDecider decide, void *context,
                                  ActionUIWinUICallback destroyContext) {
    // The decider and its context, given back on the UI thread when the window's handler lets it go.
    struct CloseDecider {
        CloseDecider(ActionUIWinUIWindowCloseDecider decide, void *context, ActionUIWinUICallback destroyContext,
                     dispatching::DispatcherQueue queue)
            : decide(decide), context(context), destroyContext(destroyContext), queue(std::move(queue)) {}
        CloseDecider(CloseDecider const &) = delete;
        CloseDecider &operator=(CloseDecider const &) = delete;
        ~CloseDecider() {
            if (destroyContext != nullptr) {
                callOnUIThread(queue, destroyContext, context);
            }
        }
        ActionUIWinUIWindowCloseDecider decide;
        void *context;
        ActionUIWinUICallback destroyContext;
        dispatching::DispatcherQueue queue;
    };
    std::shared_ptr<CloseDecider> decider;
    bool set = guarded("window on closing", [&]() {
        if (decide == nullptr) {
            return fail("window on closing", "the decider is NULL");
        }
        mux::Window typed = windowFrom(window);
        decider = std::make_shared<CloseDecider>(decide, context, destroyContext, currentQueue());
        // AppWindow's Closing comes only for the user's (the system's) close, before anything closes.
        typed.AppWindow().Closing([decider](auto &&, winrt::Microsoft::UI::Windowing::AppWindowClosingEventArgs const &args) {
            try {
                if (!decider->decide(decider->context)) {
                    args.Cancel(true);
                }
            } catch (...) {
                // Left to close: a decision that cannot be asked keeps nothing open.
            }
        });
        return true;
    });
    // Not made: the context is given back here (once made, the decider gives it back).
    if (!set && decider == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return set;
}

bool actionUIWinUIRenderToPNG(ActionUIWinUIObject *element, const char *path, ActionUIWinUICompletion completion,
                              void *context) {
    return guarded("render to PNG", [&]() {
        return startRender("render to PNG", objectAs<mux::UIElement>(element, L"UIElement"), path, completion, context);
    });
}

} // extern "C"
