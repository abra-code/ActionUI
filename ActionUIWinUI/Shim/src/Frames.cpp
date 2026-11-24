// Frames.cpp - frames drawn elsewhere, shown by a WinUI Image, the tick before each frame WinUI draws, and a watch
// on the element's window: what ActionUI's HostSurface add-on needs for a frame sink (a client presents finished
// frames; the element shows the newest one, asks the client for the next one as WinUI draws, and stops asking
// while its window is minimized).

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

// One actionUIWinUIXamlRootChangedAdd watch. destroyContext runs once, when the last copy goes: after
// actionUIWinUIXamlRootChangedRemove revokes it (or its window's XamlRoot is gone) and no call of it is running.
struct RootWatch {
    RootWatch(ActionUIWinUICallback handler, void *context, ActionUIWinUICallback destroyContext)
        : handler(handler), context(context), destroyContext(destroyContext) {}
    RootWatch(RootWatch const &) = delete;
    RootWatch &operator=(RootWatch const &) = delete;
    ~RootWatch() {
        if (destroyContext != nullptr) {
            destroyContext(context);
        }
    }

    ActionUIWinUICallback handler;
    void *context;
    ActionUIWinUICallback destroyContext;
};

// A watch's window, held weakly (a watch must not keep a closed window's content alive), and its event.
struct RootWatchEntry {
    winrt::weak_ref<mux::XamlRoot> root;
    winrt::event_token event;
};

// The watches added, by token. UI thread only.
std::map<uint64_t, RootWatchEntry> &rootWatches() {
    static std::map<uint64_t, RootWatchEntry> watches;
    return watches;
}

uint64_t nextRootWatch = 1;

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

uint64_t actionUIWinUIXamlRootChangedAdd(ActionUIWinUIObject *element, ActionUIWinUICallback handler, void *context,
                                         ActionUIWinUICallback destroyContext) {
    std::shared_ptr<RootWatch> holder;
    uint64_t token = 0;
    bool added = guarded("xaml root changed add", [&]() {
        if (handler == nullptr) {
            return fail("xaml root changed add", "the handler is NULL");
        }
        mux::XamlRoot root = objectAs<mux::UIElement>(element, L"UIElement").XamlRoot();
        if (root == nullptr) {
            return fail("xaml root changed add", "the element is in no window");
        }
        holder = std::make_shared<RootWatch>(handler, context, destroyContext);
        // In the map before the handler is registered, so nothing can fail after it is (a failure here leaves no
        // handler, and the holder's end runs destroyContext).
        auto &watches = rootWatches();
        uint64_t next = nextRootWatch;
        auto slot = watches.emplace(next, RootWatchEntry{winrt::make_weak(root), {}}).first;
        try {
            slot->second.event = root.Changed([holder](auto &&, auto &&) {
                // Held while it runs: a handler that removes itself must not free its context under it.
                std::shared_ptr<RootWatch> keep = holder;
                keep->handler(keep->context);
            });
        } catch (...) {
            watches.erase(slot);
            throw;
        }
        nextRootWatch++;
        token = next;
        return true;
    });
    if (!added && holder == nullptr && destroyContext != nullptr) {
        destroyContext(context);
    }
    return added ? token : 0;
}

void actionUIWinUIXamlRootChangedRemove(uint64_t token) {
    auto &watches = rootWatches();
    auto found = watches.find(token);
    if (found == watches.end()) {
        return;
    }
    RootWatchEntry entry = found->second;
    watches.erase(found);
    guarded("xaml root changed remove", [&]() {
        // A root already gone took its handlers with it.
        if (mux::XamlRoot root = entry.root.get()) {
            root.Changed(entry.event);
        }
        return true;
    });
}

bool actionUIWinUIElementIsHostVisible(ActionUIWinUIObject *element) {
    bool visible = false;
    guarded("element is host visible", [&]() {
        if (mux::XamlRoot root = objectAs<mux::UIElement>(element, L"UIElement").XamlRoot()) {
            visible = root.IsHostVisible();
        }
        return true;
    });
    return visible;
}

} // extern "C"
