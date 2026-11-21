// Window.cpp - windows, and rendering an element into a PNG file.

#include "ShimInternal.h"

#include <algorithm>
#include <cmath>
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
        muxc::Grid area = windowContentArea(windowFrom(window));
        area.Children().Clear();
        if (typed != nullptr) {
            area.Children().Append(typed);
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

bool actionUIWinUIWindowSendDrag(ActionUIWinUIObject *window, ActionUIWinUIObject *element, double fromX, double fromY,
                                 double toX, double toY) {
    return guarded("window send drag", [&]() {
        mux::Window typed = windowFrom(window);
        mux::UIElement target = objectAs<mux::UIElement>(element, L"UIElement");
        if (!std::isfinite(fromX) || !std::isfinite(fromY) || !std::isfinite(toX) || !std::isfinite(toY)) {
            return fail("window send drag", "a point is not finite");
        }
        mux::UIElement content = typed.Content();
        if (content == nullptr || target.XamlRoot() == nullptr || target.XamlRoot() != content.XamlRoot()) {
            return fail("window send drag", "the element is not shown in the window");
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
            return fail("window send drag", "no desktop to send the pointer's input to");
        }
        auto inputAt = [&](double x, double y, DWORD flags) {
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
        // Input goes to the desktop the user sees: a program on another one (a service's) has none to send.
        HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
        if (input == nullptr) {
            return fail("window send drag", "no access to the desktop that takes the mouse's input (not an interactive session?)");
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
            return fail("window send drag", message.c_str());
        }
        // Pressed at the start, moved there in steps (as a hand moves it), released at the end.
        std::vector<INPUT> inputs;
        inputs.push_back(inputAt(fromX, fromY, 0));
        inputs.push_back(inputAt(fromX, fromY, MOUSEEVENTF_LEFTDOWN));
        constexpr int steps = 8;
        for (int step = 1; step <= steps; step++) {
            double fraction = static_cast<double>(step) / steps;
            inputs.push_back(inputAt(fromX + (toX - fromX) * fraction, fromY + (toY - fromY) * fraction, 0));
        }
        inputs.push_back(inputAt(toX, toY, MOUSEEVENTF_LEFTUP));
        // Cleared first: SendInput does not always set it, and an earlier call's error would be reported.
        ::SetLastError(0);
        UINT sent = SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
        if (sent != inputs.size()) {
            DWORD error = GetLastError();
            if (error != 0) {
                throw winrt::hresult_error(HRESULT_FROM_WIN32(error));
            }
            return fail("window send drag", "Windows took only part of the pointer's input (another program's input in the way?)");
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

bool actionUIWinUIRenderToPNG(ActionUIWinUIObject *element, const char *path, ActionUIWinUICompletion completion,
                              void *context) {
    return guarded("render to PNG", [&]() {
        return startRender("render to PNG", objectAs<mux::UIElement>(element, L"UIElement"), path, completion, context);
    });
}

} // extern "C"
