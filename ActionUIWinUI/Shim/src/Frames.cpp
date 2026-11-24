// Frames.cpp - frames drawn elsewhere, shown by a WinUI Image, and the tick before each frame WinUI draws: what
// ActionUI's HostSurface add-on needs for a frame sink (a client presents finished frames; the element shows the
// newest one, and asks the client for the next one as WinUI draws).

#include "ShimInternal.h"

#include <cstdint>
#include <cstring>
#include <map>
#include <memory>

#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>

namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace imaging = winrt::Microsoft::UI::Xaml::Media::Imaging;

using namespace actionui_winui;

namespace {

// One actionUIWinUIRenderingAdd handler. destroyContext runs once, when the last copy goes: after
// actionUIWinUIRenderingRemove revokes it and no call of it is running.
struct FrameHandler {
    FrameHandler(ActionUIWinUIRenderingCallback handler, void *context, ActionUIWinUICallback destroyContext)
        : handler(handler), context(context), destroyContext(destroyContext) {}
    FrameHandler(FrameHandler const &) = delete;
    FrameHandler &operator=(FrameHandler const &) = delete;
    ~FrameHandler() {
        if (destroyContext != nullptr) {
            destroyContext(context);
        }
    }

    ActionUIWinUIRenderingCallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
};

// The handlers added, by token. UI thread only (CompositionTarget is the UI thread's).
std::map<uint64_t, winrt::event_token> &frameHandlers() {
    static std::map<uint64_t, winrt::event_token> handlers;
    return handlers;
}

uint64_t nextFrameHandler = 1;

} // namespace

extern "C" {

bool actionUIWinUIImageShowPixels(ActionUIWinUIObject *image, uint32_t width, uint32_t height, const uint8_t *pixels) {
    return guarded("image show pixels", [&]() {
        muxc::Image shown = objectAs<muxc::Image>(image, L"Image");
        if (pixels == nullptr || width == 0 || height == 0 || width > INT32_MAX || height > INT32_MAX) {
            return fail("image show pixels", "no pixels");
        }
        size_t rowBytes = static_cast<size_t>(width) * 4;
        if (rowBytes / 4 != width || (SIZE_MAX / rowBytes) < height) {
            return fail("image show pixels", "the frame is too large");
        }
        size_t size = rowBytes * height;
        // The image's bitmap when it is one of this size: written over, not made again for every frame.
        imaging::WriteableBitmap bitmap = shown.Source().try_as<imaging::WriteableBitmap>();
        if (bitmap == nullptr || bitmap.PixelWidth() != static_cast<int32_t>(width) ||
            bitmap.PixelHeight() != static_cast<int32_t>(height)) {
            bitmap = imaging::WriteableBitmap(static_cast<int32_t>(width), static_cast<int32_t>(height));
        }
        winrt::Windows::Storage::Streams::IBuffer buffer = bitmap.PixelBuffer();
        uint8_t *destination = buffer.data();
        if (destination == nullptr || buffer.Capacity() < size) {
            return fail("image show pixels", "the bitmap has no room for the frame");
        }
        std::memcpy(destination, pixels, size);
        bitmap.Invalidate();
        if (shown.Source() != bitmap) {
            shown.Source(bitmap);
        }
        return true;
    });
}

uint64_t actionUIWinUIRenderingAdd(ActionUIWinUIRenderingCallback handler, void *context, ActionUIWinUICallback destroyContext) {
    std::shared_ptr<FrameHandler> holder;
    uint64_t token = 0;
    bool added = guarded("rendering add", [&]() {
        if (handler == nullptr) {
            return fail("rendering add", "the handler is NULL");
        }
        holder = std::make_shared<FrameHandler>(handler, context, destroyContext);
        winrt::event_token event = media::CompositionTarget::Rendering([holder](auto &&, wf::IInspectable const &args) {
            // Held while it runs: a handler that removes itself must not free its context under it.
            std::shared_ptr<FrameHandler> keep = holder;
            double seconds = 0;
            if (auto rendering = args.try_as<media::RenderingEventArgs>()) {
                seconds = static_cast<double>(rendering.RenderingTime().count()) / 10'000'000.0;
            }
            keep->handler(keep->context, seconds);
        });
        token = nextFrameHandler++;
        frameHandlers()[token] = event;
        return true;
    });
    if (!added && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return added ? token : 0;
}

void actionUIWinUIRenderingRemove(uint64_t token) {
    auto &handlers = frameHandlers();
    auto found = handlers.find(token);
    if (found == handlers.end()) {
        return;
    }
    winrt::event_token event = found->second;
    handlers.erase(found);
    guarded("rendering remove", [&]() {
        media::CompositionTarget::Rendering(event);
        return true;
    });
}

} // extern "C"
