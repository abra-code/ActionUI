// Map.cpp - a map of OpenStreetMap's standard tiles (Web Mercator, 256-pixel tiles, zoom levels 0 to
// 19): the tiles in view are fetched with Windows' HTTP client (its cache honors the server's cache
// headers, as OpenStreetMap's tile usage policy asks), decoded and placed as images, with the
// annotations' pins and text over them. A drag pans, the wheel, a pinch, a double tap and the zoom
// buttons zoom; OpenStreetMap's attribution sits in the bottom right corner.

#include "ShimInternal.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>  // malloc
#include <cstring>
#include <deque>
#include <new>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <winrt/Microsoft.UI.Input.h>
#include <winrt/Microsoft.UI.Xaml.Automation.h>  // AutomationProperties
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.UI.h>  // Color
#include <winrt/Windows.UI.Text.h>  // FontWeight
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Web.Http.Headers.h>

namespace actionui_winui {

namespace {

namespace http = winrt::Windows::Web::Http;
namespace streams = winrt::Windows::Storage::Streams;
namespace imaging = winrt::Microsoft::UI::Xaml::Media::Imaging;
namespace input = winrt::Microsoft::UI::Xaml::Input;

constexpr double tileSize = 256;
constexpr int minLevel = 0;
constexpr int maxLevel = 19;
constexpr double latitudeLimit = 85.05112878;
constexpr double pi = 3.14159265358979323846;
// Tiles fetched at once, and decoded tiles kept.
constexpr int maxFetches = 4;
constexpr size_t maxCached = 512;

// A tile of the world: level z, column x (0 to 2^z - 1), row y.
uint64_t tileKey(int z, int64_t x, int64_t y) {
    return (static_cast<uint64_t>(z) << 56) | (static_cast<uint64_t>(x) << 28) | static_cast<uint64_t>(y);
}

// A tile in view: as tileKey, with a column that may be outside 0 to 2^z - 1 where the world repeats
// across a wide view.
uint64_t placeKey(int z, int64_t x, int64_t y) {
    return (static_cast<uint64_t>(z) << 56) | (static_cast<uint64_t>(x + (int64_t(1) << 26)) << 28) | static_cast<uint64_t>(y);
}

// An annotation's view, placed so that its pin's tip (tipY below the view's top, at its horizontal
// middle) is on the coordinate.
struct Marker {
    mux::FrameworkElement view{nullptr};
    double latitude;
    double longitude;
    double tipY;
};

// An annotation's view is this wide, its text wrapped and centered in it.
constexpr double markerWidth = 160;
// Room between the pin's tip and the text under it.
constexpr double pinTextGap = 2;

struct Placed {
    muxc::Image image{nullptr};
    int level;
    int64_t x;
    int64_t y;
    uint64_t tile;
};

// A map's own state, held by the handlers on its root and found by the root's identity.
struct MapData {
    winrt::weak_ref<muxc::Grid> root;
    muxc::Canvas backdrop{nullptr};
    muxc::Canvas tiles{nullptr};
    muxc::Canvas markerLayer{nullptr};
    std::vector<Marker> markers;
    muxc::StackPanel zoomButtons{nullptr};
    http::HttpClient client{nullptr};
    double latitude = 0;
    double longitude = 0;
    double zoom = 1;
    double width = 0;
    double height = 0;
    bool canPan = true;
    bool canZoom = true;
    bool pressed = false;
    bool manipulating = false;
    // The tiles shown at the level in use, and those of the level before, kept under them until the
    // new ones have come.
    int level = -1;
    std::unordered_map<uint64_t, Placed> shown;
    std::unordered_map<uint64_t, Placed> previous;
    // The decoded tiles, oldest first in `cacheOrder`.
    std::unordered_map<uint64_t, imaging::BitmapImage> cache;
    std::deque<uint64_t> cacheOrder;
    // The tiles in view at the last layout; waiting to be fetched; being fetched; that failed.
    std::unordered_set<uint64_t> wanted;
    std::deque<uint64_t> waiting;
    std::unordered_set<uint64_t> requested;
    int fetching = 0;
    std::unordered_set<uint64_t> failed;
    std::string firstFailure;
    int loaded = 0;
    std::shared_ptr<EventHandler> moved;
};

std::unordered_map<void *, std::weak_ptr<MapData>> &maps() {
    static auto *all = new std::unordered_map<void *, std::weak_ptr<MapData>>();
    return *all;
}

void *identity(muxc::Grid const &root) {
    return winrt::get_abi(root.as<wf::IUnknown>());
}

std::shared_ptr<MapData> dataOf(ActionUIWinUIObject *object) {
    muxc::Grid root = objectAs<muxc::Grid>(object, L"Grid");
    auto found = maps().find(identity(root));
    if (found == maps().end()) {
        throw winrt::hresult_invalid_argument(L"the map was not made by actionUIWinUIMapCreate");
    }
    std::shared_ptr<MapData> data = found->second.lock();
    if (data == nullptr) {
        maps().erase(found);
        throw winrt::hresult_invalid_argument(L"the map is gone");
    }
    return data;
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

double clamp(double value, double low, double high) {
    return value < low ? low : (value > high ? high : value);
}

// The world's width (and height) in pixels at `zoom`.
double worldSize(double zoom) {
    return tileSize * std::pow(2.0, zoom);
}

double longitudeToX(double longitude, double world) {
    return (longitude + 180.0) / 360.0 * world;
}

double latitudeToY(double latitude, double world) {
    double radians = clamp(latitude, -latitudeLimit, latitudeLimit) * pi / 180.0;
    return (1.0 - std::asinh(std::tan(radians)) / pi) / 2.0 * world;
}

double xToLongitude(double x, double world) {
    double longitude = x / world * 360.0 - 180.0;
    // Into -180 to 180: the world repeats across.
    longitude = std::fmod(longitude + 180.0, 360.0);
    if (longitude < 0) {
        longitude += 360.0;
    }
    return longitude - 180.0;
}

double yToLatitude(double y, double world) {
    double n = pi * (1.0 - 2.0 * clamp(y, 0, world) / world);
    return clamp(std::atan(std::sinh(n)) * 180.0 / pi, -latitudeLimit, latitudeLimit);
}

// Runs an event handler's body: nothing may leave a WinRT event handler (WinUI would take it for the
// program's unhandled error), and laying out the tiles changes XAML's tree, which can throw.
template <typename Body>
void handling(Body &&body) noexcept {
    try {
        body();
    } catch (...) {
    }
}

void notify(std::shared_ptr<MapData> const &data) {
    if (data->moved != nullptr) {
        data->moved->fire();
    }
}

void startFetches(std::shared_ptr<MapData> const &data);
void layoutTiles(std::shared_ptr<MapData> const &data);

void remember(std::shared_ptr<MapData> const &data, uint64_t tile, imaging::BitmapImage const &bitmap) {
    if (data->cache.emplace(tile, bitmap).second) {
        data->cacheOrder.push_back(tile);
    }
    // The oldest go first, but not those in view (they go back to the end): at most one pass.
    size_t looked = 0;
    while (data->cache.size() > maxCached && looked < data->cacheOrder.size()) {
        uint64_t oldest = data->cacheOrder.front();
        data->cacheOrder.pop_front();
        looked += 1;
        if (data->wanted.count(oldest) != 0) {
            data->cacheOrder.push_back(oldest);
            continue;
        }
        data->cache.erase(oldest);
    }
}

// Fetches and decodes one tile, then shows it where it is still in view. Resumes on the UI thread
// after each wait (the caller's apartment).
winrt::fire_and_forget fetchTile(std::weak_ptr<MapData> weak, uint64_t tile, int z, int64_t x, int64_t y) {
    std::string failure;
    imaging::BitmapImage bitmap{nullptr};
    try {
        http::HttpClient client{nullptr};
        if (std::shared_ptr<MapData> data = weak.lock()) {
            client = data->client;
        }
        if (client == nullptr) {
            co_return;
        }
        wf::Uri uri(L"https://tile.openstreetmap.org/" + winrt::to_hstring(z) + L"/" + winrt::to_hstring(x) + L"/" +
                    winrt::to_hstring(y) + L".png");
        http::HttpResponseMessage response = co_await client.GetAsync(uri);
        if (!response.IsSuccessStatusCode()) {
            failure = "the tile server answered " + std::to_string(static_cast<int32_t>(response.StatusCode()));
        } else {
            streams::IBuffer body = co_await response.Content().ReadAsBufferAsync();
            streams::InMemoryRandomAccessStream stream;
            co_await stream.WriteAsync(body);
            stream.Seek(0);
            imaging::BitmapImage decoded;
            co_await decoded.SetSourceAsync(stream);
            bitmap = decoded;
        }
    } catch (winrt::hresult_error const &error) {
        failure = winrt::to_string(error.message());
        if (failure.empty()) {
            failure = "the tile could not be loaded";
        }
    } catch (std::exception const &error) {
        failure = error.what();
    } catch (...) {
        failure = "an unknown C++ exception";
    }
    // Nothing may leave a fire_and_forget coroutine.
    try {
        std::shared_ptr<MapData> data = weak.lock();
        if (data == nullptr) {
            co_return;
        }
        data->fetching -= 1;
        data->requested.erase(tile);
        if (bitmap != nullptr) {
            data->loaded += 1;
            remember(data, tile, bitmap);
            layoutTiles(data);
        } else {
            data->failed.insert(tile);
            if (data->firstFailure.empty()) {
                data->firstFailure = failure.empty() ? std::string("the tile could not be loaded") : failure;
            }
            startFetches(data);
        }
    } catch (...) {
    }
}

void startFetches(std::shared_ptr<MapData> const &data) {
    while (data->fetching < maxFetches && !data->waiting.empty()) {
        uint64_t tile = data->waiting.front();
        data->waiting.pop_front();
        // Out of view since it was asked for: not fetched.
        if (data->wanted.count(tile) == 0 || data->cache.count(tile) != 0) {
            data->requested.erase(tile);
            continue;
        }
        int z = static_cast<int>(tile >> 56);
        int64_t x = static_cast<int64_t>((tile >> 28) & ((uint64_t(1) << 28) - 1));
        int64_t y = static_cast<int64_t>(tile & ((uint64_t(1) << 28) - 1));
        data->fetching += 1;
        fetchTile(data, tile, z, x, y);
    }
}

// Places `placed` for the view: its level drawn at the zoom in use.
void place(std::shared_ptr<MapData> const &data, Placed const &placed, double left, double top) {
    double side = tileSize * std::pow(2.0, data->zoom - placed.level);
    // A hair larger than the tile, so no seam shows between neighbors at fractional positions.
    placed.image.Width(side + 0.5);
    placed.image.Height(side + 0.5);
    muxc::Canvas::SetLeft(placed.image, placed.x * side - left);
    muxc::Canvas::SetTop(placed.image, placed.y * side - top);
}

// Places the annotations' views over the map at the camera; one whose place is out of view is placed
// there too (the layer clips nothing, the map does). Where the world repeats across, the copy nearest
// the center is the one shown.
void layoutMarkers(std::shared_ptr<MapData> const &data) {
    double world = worldSize(data->zoom);
    double centerX = longitudeToX(data->longitude, world);
    double left = centerX - data->width / 2;
    double top = latitudeToY(data->latitude, world) - data->height / 2;
    for (Marker const &marker : data->markers) {
        // The degrees east of the center, -180 to 180, in one step: a host's longitude far outside
        // -180 to 180 (1e20) would take a loop of world widths forever.
        double east = std::remainder(marker.longitude - data->longitude, 360.0);
        double x = centerX + east / 360.0 * world;
        double y = latitudeToY(marker.latitude, world);
        muxc::Canvas::SetLeft(marker.view, x - left - markerWidth / 2);
        muxc::Canvas::SetTop(marker.view, y - top - marker.tipY);
    }
}

// Shows the tiles that cover the view at the camera, fetching the missing ones.
void layoutTiles(std::shared_ptr<MapData> const &data) {
    if (data->width <= 0 || data->height <= 0) {
        return;
    }
    int level = static_cast<int>(clamp(std::floor(data->zoom + 0.5), minLevel, maxLevel));
    if (level != data->level) {
        // The level in use changes: the tiles shown become the backdrop until the new ones come.
        // (An element has one parent: the tiles leave theirs first.)
        data->tiles.Children().Clear();
        data->backdrop.Children().Clear();
        data->previous.clear();
        if (data->level >= 0) {
            for (auto &entry : data->shown) {
                if (entry.second.image.Source() != nullptr) {
                    data->backdrop.Children().Append(entry.second.image);
                    data->previous.emplace(entry.first, entry.second);
                }
            }
        }
        data->shown.clear();
        data->level = level;
    }
    double world = worldSize(data->zoom);
    double side = tileSize * std::pow(2.0, data->zoom - level);
    double left = longitudeToX(data->longitude, world) - data->width / 2;
    double top = latitudeToY(data->latitude, world) - data->height / 2;
    int64_t count = int64_t(1) << level;
    int64_t firstX = static_cast<int64_t>(std::floor(left / side));
    int64_t lastX = static_cast<int64_t>(std::floor((left + data->width) / side));
    int64_t firstY = static_cast<int64_t>(clamp(std::floor(top / side), 0, double(count - 1)));
    int64_t lastY = static_cast<int64_t>(clamp(std::floor((top + data->height) / side), 0, double(count - 1)));
    // At most a few world widths across (zoom 0 in a wide view).
    if (lastX - firstX > 4 * count + 8) {
        lastX = firstX + 4 * count + 8;
    }
    std::unordered_set<uint64_t> inView;
    data->wanted.clear();
    bool complete = true;
    for (int64_t y = firstY; y <= lastY; y++) {
        for (int64_t x = firstX; x <= lastX; x++) {
            int64_t column = ((x % count) + count) % count;
            uint64_t tile = tileKey(level, column, y);
            uint64_t key = placeKey(level, x, y);
            inView.insert(key);
            data->wanted.insert(tile);
            auto found = data->shown.find(key);
            if (found == data->shown.end()) {
                muxc::Image image;
                image.Stretch(mux::Media::Stretch::Fill);
                image.IsHitTestVisible(false);
                found = data->shown.emplace(key, Placed{image, level, x, y, tile}).first;
                data->tiles.Children().Append(image);
            }
            Placed &placed = found->second;
            if (placed.image.Source() == nullptr) {
                auto cached = data->cache.find(tile);
                if (cached != data->cache.end()) {
                    placed.image.Source(cached->second);
                } else {
                    complete = false;
                    if (data->requested.count(tile) == 0 && data->failed.count(tile) == 0) {
                        data->requested.insert(tile);
                        data->waiting.push_back(tile);
                    }
                }
            }
            place(data, placed, left, top);
        }
    }
    // Tiles gone out of view.
    for (auto entry = data->shown.begin(); entry != data->shown.end();) {
        if (inView.count(entry->first) == 0) {
            uint32_t index = 0;
            if (data->tiles.Children().IndexOf(entry->second.image, index)) {
                data->tiles.Children().RemoveAt(index);
            }
            entry = data->shown.erase(entry);
        } else {
            ++entry;
        }
    }
    if (complete) {
        data->backdrop.Children().Clear();
        data->previous.clear();
    } else {
        for (auto &entry : data->previous) {
            place(data, entry.second, left, top);
        }
    }
    layoutMarkers(data);
    startFetches(data);
}

// The camera moved: the tiles follow, and the handler is told.
void setCamera(std::shared_ptr<MapData> const &data, double latitude, double longitude, double zoom) {
    data->latitude = clamp(latitude, -latitudeLimit, latitudeLimit);
    // Wrapped only when outside: the round trip through pixels changes a longitude near 0 in its last
    // digits (-0.1246 comes back as -0.12459999999998672), and a host's value must stay as given.
    if (longitude < -180.0 || longitude >= 180.0) {
        double world = worldSize(0);
        longitude = xToLongitude(longitudeToX(longitude, world), world);
    }
    data->longitude = longitude;
    data->zoom = clamp(zoom, minLevel, maxLevel);
    layoutTiles(data);
    notify(data);
}

// Moves the map by (dx, dy) pixels, as a drag does: the point under the pointer stays under it.
void panBy(std::shared_ptr<MapData> const &data, double dx, double dy) {
    double world = worldSize(data->zoom);
    double x = longitudeToX(data->longitude, world) - dx;
    double y = latitudeToY(data->latitude, world) - dy;
    setCamera(data, yToLatitude(y, world), xToLongitude(x, world), data->zoom);
}

// Zooms to `zoom` keeping the place at (px, py) in the view where it is.
void zoomAround(std::shared_ptr<MapData> const &data, double zoom, double px, double py) {
    zoom = clamp(zoom, minLevel, maxLevel);
    double world = worldSize(data->zoom);
    double offsetX = px - data->width / 2;
    double offsetY = py - data->height / 2;
    // About the center (the zoom buttons): the center stays exactly, not moved by the round trip
    // through pixels, so a zoom alone changes no value.
    if (offsetX == 0 && offsetY == 0) {
        setCamera(data, data->latitude, data->longitude, zoom);
        return;
    }
    double pointX = longitudeToX(data->longitude, world) + offsetX;
    double pointY = latitudeToY(data->latitude, world) + offsetY;
    double factor = std::pow(2.0, zoom - data->zoom);
    double newWorld = worldSize(zoom);
    double centerX = pointX * factor - offsetX;
    double centerY = pointY * factor - offsetY;
    setCamera(data, yToLatitude(centerY, newWorld), xToLongitude(centerX, newWorld), zoom);
}

void applyInteraction(std::shared_ptr<MapData> const &data) {
    muxc::Grid root = data->root.get();
    if (root == nullptr) {
        return;
    }
    input::ManipulationModes modes = input::ManipulationModes::None;
    if (data->canPan) {
        modes = modes | input::ManipulationModes::TranslateX | input::ManipulationModes::TranslateY |
                input::ManipulationModes::TranslateInertia;
    }
    if (data->canZoom) {
        modes = modes | input::ManipulationModes::Scale;
    }
    root.ManipulationMode(modes == input::ManipulationModes::None ? input::ManipulationModes::System : modes);
    data->zoomButtons.Visibility(data->canZoom ? mux::Visibility::Visible : mux::Visibility::Collapsed);
}

muxc::Button zoomButton(const wchar_t *text, const wchar_t *name) {
    muxc::Button button;
    button.Content(winrt::box_value(winrt::hstring(text)));
    button.Width(32);
    button.Height(32);
    button.Padding(mux::Thickness{0, 0, 0, 0});
    button.HorizontalContentAlignment(mux::HorizontalAlignment::Center);
    button.VerticalContentAlignment(mux::VerticalAlignment::Center);
    mux::Automation::AutomationProperties::SetName(button, name);
    return button;
}

// OpenStreetMap's attribution, as its license asks: a link to its copyright page.
mux::FrameworkElement attribution() {
    namespace docs = winrt::Microsoft::UI::Xaml::Documents;
    muxc::TextBlock text;
    text.FontSize(11);
    text.Foreground(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0xFF, 0x33, 0x33, 0x33}));
    docs::Run before;
    before.Text(L"\u00A9 ");
    docs::Hyperlink link;
    link.NavigateUri(wf::Uri(L"https://www.openstreetmap.org/copyright"));
    docs::Run name;
    name.Text(L"OpenStreetMap");
    link.Inlines().Append(name);
    docs::Run after;
    after.Text(L" contributors");
    text.Inlines().Append(before);
    text.Inlines().Append(link);
    text.Inlines().Append(after);
    muxc::Border border;
    border.Background(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0xB3, 0xFF, 0xFF, 0xFF}));
    border.Padding(mux::Thickness{4, 1, 4, 1});
    border.HorizontalAlignment(mux::HorizontalAlignment::Right);
    border.VerticalAlignment(mux::VerticalAlignment::Bottom);
    border.Child(text);
    return border;
}

} // namespace

} // namespace actionui_winui

using namespace actionui_winui;

extern "C" {

ActionUIWinUIObject *actionUIWinUIMapCreate(const char *userAgent) {
    return guardedObject("map create", [&]() {
        muxc::Grid root;
        // The land color of OpenStreetMap's tiles, under tiles still coming; hit-testable everywhere.
        root.Background(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0xFF, 0xF2, 0xEF, 0xE9}));
        mux::Automation::AutomationProperties::SetName(root, L"Map");
        auto data = std::make_shared<MapData>();
        data->root = winrt::make_weak(root);
        data->backdrop = muxc::Canvas();
        data->tiles = muxc::Canvas();
        data->backdrop.IsHitTestVisible(false);
        data->tiles.IsHitTestVisible(false);
        root.Children().Append(data->backdrop);
        root.Children().Append(data->tiles);
        // The annotations take no input: a drag or a click that starts on one goes to the map.
        data->markerLayer = muxc::Canvas();
        data->markerLayer.IsHitTestVisible(false);
        root.Children().Append(data->markerLayer);
        root.Children().Append(attribution());

        data->zoomButtons = muxc::StackPanel();
        data->zoomButtons.Spacing(4);
        data->zoomButtons.Margin(mux::Thickness{8, 8, 8, 8});
        data->zoomButtons.HorizontalAlignment(mux::HorizontalAlignment::Right);
        data->zoomButtons.VerticalAlignment(mux::VerticalAlignment::Top);
        muxc::Button zoomIn = zoomButton(L"+", L"Zoom in");
        muxc::Button zoomOut = zoomButton(L"\u2212", L"Zoom out");
        data->zoomButtons.Children().Append(zoomIn);
        data->zoomButtons.Children().Append(zoomOut);
        root.Children().Append(data->zoomButtons);

        data->client = http::HttpClient();
        std::string agent = userAgent != nullptr && userAgent[0] != '\0' ? userAgent : "ActionUI-app";
        // A name the header refuses: the requests still name ActionUI, as the policy asks.
        if (!data->client.DefaultRequestHeaders().TryAppendWithoutValidation(L"User-Agent", winrt::to_hstring(agent))) {
            data->client.DefaultRequestHeaders().TryAppendWithoutValidation(L"User-Agent", L"ActionUI-app");
        }

        // The handlers on the root hold the data; those on the root's own children (the buttons) hold
        // it weakly, as the data holds them.
        std::weak_ptr<MapData> weak = data;
        zoomIn.Click([weak](auto &&, auto &&) {
            handling([&]() {
                if (std::shared_ptr<MapData> held = weak.lock()) {
                    zoomAround(held, std::round(held->zoom) + 1, held->width / 2, held->height / 2);
                }
            });
        });
        zoomOut.Click([weak](auto &&, auto &&) {
            handling([&]() {
                if (std::shared_ptr<MapData> held = weak.lock()) {
                    zoomAround(held, std::round(held->zoom) - 1, held->width / 2, held->height / 2);
                }
            });
        });
        root.SizeChanged([data](wf::IInspectable const &sender, mux::SizeChangedEventArgs const &args) {
            handling([&]() {
                data->width = args.NewSize().Width;
                data->height = args.NewSize().Height;
                mux::Media::RectangleGeometry clip;
                clip.Rect(wf::Rect{0, 0, static_cast<float>(data->width), static_cast<float>(data->height)});
                sender.as<muxc::Grid>().Clip(clip);
                layoutTiles(data);
            });
        });
        root.PointerPressed([data](auto &&, auto &&) { data->pressed = true; });
        auto released = [data](auto &&, auto &&) {
            if (data->pressed) {
                data->pressed = false;
                notify(data);
            }
        };
        root.PointerReleased(released);
        root.PointerCanceled(released);
        root.PointerCaptureLost(released);
        // A button released outside the map never reaches it; a drag still going counts as moving
        // through its manipulation.
        root.PointerExited(released);
        root.ManipulationStarted([data](auto &&, auto &&) { data->manipulating = true; });
        root.ManipulationDelta([data](auto &&, input::ManipulationDeltaRoutedEventArgs const &args) {
            handling([&]() {
                winrt::Microsoft::UI::Input::ManipulationDelta delta = args.Delta();
                if (data->canZoom && delta.Scale > 0 && delta.Scale != 1) {
                    zoomAround(data, data->zoom + std::log2(delta.Scale), args.Position().X, args.Position().Y);
                }
                if (data->canPan && (delta.Translation.X != 0 || delta.Translation.Y != 0)) {
                    panBy(data, delta.Translation.X, delta.Translation.Y);
                }
                args.Handled(true);
            });
        });
        root.ManipulationCompleted([data](auto &&, auto &&) {
            data->manipulating = false;
            notify(data);
        });
        root.PointerWheelChanged([data](wf::IInspectable const &sender, input::PointerRoutedEventArgs const &args) {
            handling([&]() {
                if (!data->canZoom) {
                    return;
                }
                winrt::Microsoft::UI::Input::PointerPoint point = args.GetCurrentPoint(sender.as<mux::UIElement>());
                if (point.Properties().IsHorizontalMouseWheel()) {
                    return;
                }
                // A notch (120) is a zoom level; a precision touchpad's smaller steps zoom smoothly.
                double steps = point.Properties().MouseWheelDelta() / 120.0;
                zoomAround(data, data->zoom + steps, point.Position().X, point.Position().Y);
                args.Handled(true);
            });
        });
        root.DoubleTapped([data](wf::IInspectable const &sender, input::DoubleTappedRoutedEventArgs const &args) {
            handling([&]() {
                // On the map itself: not on the zoom buttons or the attribution's link.
                if (!data->canZoom || args.OriginalSource() != sender) {
                    return;
                }
                wf::Point position = args.GetPosition(sender.as<mux::UIElement>());
                zoomAround(data, std::round(data->zoom) + 1, position.X, position.Y);
                args.Handled(true);
            });
        });
        applyInteraction(data);
        maps()[identity(root)] = data;
        return toObject(root);
    });
}

bool actionUIWinUIMapSetAnnotations(ActionUIWinUIObject *map, const ActionUIWinUIMapAnnotation *annotations, size_t count) {
    return guarded("map set annotations", [&]() {
        std::shared_ptr<MapData> data = dataOf(map);
        if (annotations == nullptr && count > 0) {
            return fail("map set annotations", "no annotations to read");
        }
        // Built first, so a failure leaves the old ones shown.
        std::vector<Marker> markers;
        for (size_t index = 0; index < count; index++) {
            ActionUIWinUIMapAnnotation const &annotation = annotations[index];
            if (!std::isfinite(annotation.latitude) || !std::isfinite(annotation.longitude)) {
                continue;
            }
            muxc::StackPanel view;
            view.Width(markerWidth);
            view.IsHitTestVisible(false);
            double tipY = 0;
            if (annotation.pin != nullptr) {
                mux::FrameworkElement pin = objectAs<mux::FrameworkElement>(annotation.pin, L"FrameworkElement");
                // An element has one parent: a pin shown before leaves its old view.
                if (auto parent = winrt::Microsoft::UI::Xaml::Media::VisualTreeHelper::GetParent(pin).try_as<muxc::Panel>()) {
                    uint32_t at = 0;
                    if (parent.Children().IndexOf(pin, at)) {
                        parent.Children().RemoveAt(at);
                    }
                }
                pin.HorizontalAlignment(mux::HorizontalAlignment::Center);
                pin.Width(annotation.pinSide);
                pin.Height(annotation.pinSide);
                view.Children().Append(pin);
                tipY = annotation.pinSide - annotation.pinTip;
            }
            muxc::StackPanel lines;
            for (int line = 0; line < 2; line++) {
                const char *text = line == 0 ? annotation.title : annotation.subtitle;
                if (text == nullptr || text[0] == '\0') {
                    continue;
                }
                muxc::TextBlock block;
                block.Text(toHString(text));
                block.FontSize(12);
                if (line == 0) {
                    block.FontWeight(winrt::Windows::UI::Text::FontWeight{600});  // semibold
                }
                block.TextWrapping(mux::TextWrapping::Wrap);
                block.TextAlignment(mux::TextAlignment::Center);
                block.HorizontalAlignment(mux::HorizontalAlignment::Center);
                // Dark on the light tiles in either theme, as the tiles stay light.
                block.Foreground(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0xD9, 0, 0, 0}));
                lines.Children().Append(block);
            }
            if (lines.Children().Size() > 0) {
                // A light plate under the text, so it reads over roads and labels.
                muxc::Border plate;
                plate.Background(mux::Media::SolidColorBrush(winrt::Windows::UI::Color{0xBF, 0xFF, 0xFF, 0xFF}));
                plate.CornerRadius(mux::CornerRadius{4, 4, 4, 4});
                plate.Padding(mux::Thickness{4, 1, 4, 1});
                plate.HorizontalAlignment(mux::HorizontalAlignment::Center);
                plate.Margin(mux::Thickness{0, pinTextGap - (annotation.pin != nullptr ? annotation.pinTip : 0), 0, 0});
                plate.Child(lines);
                view.Children().Append(plate);
            }
            markers.push_back(Marker{view, annotation.latitude, annotation.longitude, tipY});
        }
        data->markerLayer.Children().Clear();
        data->markers = std::move(markers);
        for (Marker const &marker : data->markers) {
            data->markerLayer.Children().Append(marker.view);
        }
        layoutMarkers(data);
        return true;
    });
}

bool actionUIWinUIMapSetCamera(ActionUIWinUIObject *map, double latitude, double longitude, double zoom) {
    return guarded("map set camera", [&]() {
        std::shared_ptr<MapData> data = dataOf(map);
        if (!std::isfinite(latitude) || !std::isfinite(longitude)) {
            return fail("map set camera", "the coordinate is not a number");
        }
        setCamera(data, latitude, longitude, std::isfinite(zoom) && zoom >= 0 ? zoom : data->zoom);
        return true;
    });
}

bool actionUIWinUIMapGetCamera(ActionUIWinUIObject *map, ActionUIWinUIMapCamera *camera) {
    return guarded("map get camera", [&]() {
        if (camera == nullptr) {
            return fail("map get camera", "no camera to write to");
        }
        std::shared_ptr<MapData> data = dataOf(map);
        *camera = ActionUIWinUIMapCamera{data->latitude, data->longitude, data->zoom, data->pressed || data->manipulating};
        return true;
    });
}

bool actionUIWinUIMapSetInteraction(ActionUIWinUIObject *map, bool pan, bool zoom) {
    return guarded("map set interaction", [&]() {
        std::shared_ptr<MapData> data = dataOf(map);
        if (data->canPan != pan || data->canZoom != zoom) {
            data->canPan = pan;
            data->canZoom = zoom;
            applyInteraction(data);
        }
        return true;
    });
}

char *actionUIWinUIMapCopyStatus(ActionUIWinUIObject *map) {
    char *copy = nullptr;
    guarded("map copy status", [&]() {
        std::shared_ptr<MapData> data = dataOf(map);
        std::string status = std::to_string(data->loaded) + " tiles loaded, " + std::to_string(data->failed.size()) + " failed";
        if (!data->firstFailure.empty()) {
            status += " (" + data->firstFailure + ")";
        }
        copy = copyString(status);
        return true;
    });
    return copy;
}

bool actionUIWinUIMapOnMoved(ActionUIWinUIObject *map, ActionUIWinUICallback handler, void *context,
                            ActionUIWinUICallback destroyContext) {
    return registerHandler("map on moved", handler, context, destroyContext,
                           [&](std::shared_ptr<EventHandler> const &holder) { dataOf(map)->moved = holder; });
}

} // extern "C"
