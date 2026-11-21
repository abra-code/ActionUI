// Video.cpp - a video player: WinUI's MediaPlayerElement with Windows' transport controls over it,
// playing through one MediaPlayer for its whole life, so a new video keeps the volume and mute chosen.

#include "ShimInternal.h"

#include <cstdlib>  // malloc
#include <cstring>
#include <new>
#include <string>
#include <unordered_map>

#include <winrt/Windows.Media.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

namespace actionui_winui {

namespace {

namespace playback = winrt::Windows::Media::Playback;
namespace media = winrt::Windows::Media::Core;

// A player's own state, held by the handlers on its MediaPlayer (which its element holds) and found
// by the element's identity. Read and written on the UI thread only: the MediaPlayer raises its
// events on other threads, which send what they read here.
struct VideoData {
    dispatching::DispatcherQueue queue{nullptr};
    // The source shown, to tell an event for it from one for the source before.
    wf::IInspectable source{nullptr};
    // "none", "opening", "opened W x H" or "failed: " and why.
    std::string status = "none";
    std::shared_ptr<EventHandler> changed;
};

std::unordered_map<void *, std::weak_ptr<VideoData>> &videoPlayers() {
    static auto *players = new std::unordered_map<void *, std::weak_ptr<VideoData>>();
    return *players;
}

void *identity(muxc::MediaPlayerElement const &element) {
    return winrt::get_abi(element.as<wf::IUnknown>());
}

std::shared_ptr<VideoData> dataOf(ActionUIWinUIObject *object) {
    muxc::MediaPlayerElement element = objectAs<muxc::MediaPlayerElement>(object, L"MediaPlayerElement");
    auto found = videoPlayers().find(identity(element));
    if (found == videoPlayers().end()) {
        throw winrt::hresult_invalid_argument(L"the video player was not made by actionUIWinUIVideoPlayerCreate");
    }
    std::shared_ptr<VideoData> data = found->second.lock();
    if (data == nullptr) {
        videoPlayers().erase(found);
        throw winrt::hresult_invalid_argument(L"the video player is gone");
    }
    return data;
}

playback::MediaPlayer playerOf(ActionUIWinUIObject *object) {
    playback::MediaPlayer player = objectAs<muxc::MediaPlayerElement>(object, L"MediaPlayerElement").MediaPlayer();
    if (player == nullptr) {
        throw winrt::hresult_invalid_argument(L"the video player has no MediaPlayer");
    }
    return player;
}

// Sets the status, on the UI thread, when the event was for the source still shown (one set since is
// reported by its own events), and tells the handler. The source is the player's when the event came:
// an event of a source replaced while it was opening, coming after the new one was set, is taken for
// the new one's, and the new one's own event corrects the status.
void report(std::weak_ptr<VideoData> const &weak, wf::IInspectable const &source, std::string status) {
    std::shared_ptr<VideoData> data = weak.lock();
    if (data == nullptr || data->queue == nullptr) {
        return;
    }
    // Fails quietly once the UI thread's queue has shut down.
    data->queue.TryEnqueue([weak, source, status = std::move(status)]() {
        // Nothing may leave a DispatcherQueue handler.
        try {
            std::shared_ptr<VideoData> held = weak.lock();
            if (held == nullptr || held->source == nullptr || source == nullptr ||
                winrt::get_abi(held->source.as<wf::IUnknown>()) != winrt::get_abi(source.as<wf::IUnknown>())) {
                return;
            }
            held->status = status;
            if (held->changed != nullptr) {
                held->changed->fire();
            }
        } catch (...) {
        }
    });
}

// Why the MediaPlayer could not play, from its failure event.
std::string failureText(playback::MediaPlayerFailedEventArgs const &args) {
    std::string text = winrt::to_string(args.ErrorMessage());
    if (text.empty() && FAILED(args.ExtendedErrorCode())) {
        text = winrt::to_string(winrt::hresult_error(args.ExtendedErrorCode()).message());
    }
    if (text.empty()) {
        switch (args.Error()) {
        case playback::MediaPlayerError::Aborted:
            text = "the opening was aborted";
            break;
        case playback::MediaPlayerError::NetworkError:
            text = "a network error";
            break;
        case playback::MediaPlayerError::DecodingError:
            text = "the video could not be decoded";
            break;
        case playback::MediaPlayerError::SourceNotSupported:
            text = "the video's format is not supported";
            break;
        default:
            text = "an unknown error";
            break;
        }
    }
    return text;
}

// A new UTF-8 string the caller frees with actionUIWinUIFreeString.
char *copyString(std::string const &utf8) {
    char *copy = static_cast<char *>(malloc(utf8.size() + 1));
    if (copy == nullptr) {
        throw std::bad_alloc();
    }
    memcpy(copy, utf8.data(), utf8.size());
    copy[utf8.size()] = '\0';
    return copy;
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIVideoPlayerCreate(void) {
    return guardedObject("video player create", []() {
        muxc::MediaPlayerElement element;
        element.AreTransportControlsEnabled(true);
        element.Stretch(mux::Media::Stretch::Uniform);
        auto data = std::make_shared<VideoData>();
        data->queue = currentQueue();
        playback::MediaPlayer player;
        player.AutoPlay(false);
        // The handlers hold the data (the element holds the player, the player its handlers); the data
        // holds neither. They run on a worker thread, and nothing may leave them (a closed player's
        // getters throw).
        player.MediaOpened([data](playback::MediaPlayer const &sender, auto &&) {
            try {
                playback::MediaPlaybackSession session = sender.PlaybackSession();
                std::string status = "opened " + std::to_string(session.NaturalVideoWidth()) + " x " +
                                     std::to_string(session.NaturalVideoHeight());
                report(data, sender.Source(), std::move(status));
            } catch (...) {
            }
        });
        player.MediaFailed([data](playback::MediaPlayer const &sender, playback::MediaPlayerFailedEventArgs const &args) {
            try {
                report(data, sender.Source(), "failed: " + failureText(args));
            } catch (...) {
            }
        });
        element.SetMediaPlayer(player);
        videoPlayers()[identity(element)] = data;
        return toObject(element);
    });
}

bool actionUIWinUIVideoPlayerSetSource(ActionUIWinUIObject *videoPlayer, const char *url) {
    return guarded("video player set source", [&]() {
        std::shared_ptr<VideoData> data = dataOf(videoPlayer);
        playback::MediaPlayer player = playerOf(videoPlayer);
        player.Pause();
        if (url == nullptr || url[0] == '\0') {
            data->source = nullptr;
            data->status = "none";
            player.Source(nullptr);
            return true;
        }
        wf::Uri uri{nullptr};
        try {
            uri = wf::Uri(toHString(url));
        } catch (winrt::hresult_error const &) {
            data->source = nullptr;
            data->status = "failed: not an absolute URL";
            player.Source(nullptr);
            return true;
        }
        media::MediaSource source = media::MediaSource::CreateFromUri(uri);
        data->source = source;
        data->status = "opening";
        player.Source(source);
        return true;
    });
}

bool actionUIWinUIVideoPlayerSetPlaying(ActionUIWinUIObject *videoPlayer, bool playing) {
    return guarded("video player set playing", [&]() {
        playback::MediaPlayer player = playerOf(videoPlayer);
        if (playing) {
            player.Play();
        } else {
            player.Pause();
        }
        return true;
    });
}

char *actionUIWinUIVideoPlayerCopyStatus(ActionUIWinUIObject *videoPlayer) {
    char *copy = nullptr;
    guarded("video player copy status", [&]() {
        copy = copyString(dataOf(videoPlayer)->status);
        return true;
    });
    return copy;
}

bool actionUIWinUIVideoPlayerOnChanged(ActionUIWinUIObject *videoPlayer, ActionUIWinUICallback handler, void *context,
                                       ActionUIWinUICallback destroyContext) {
    return registerHandler("video player on changed", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) { dataOf(videoPlayer)->changed = holder; });
}

} // extern "C"
