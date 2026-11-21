// Location.cpp - the user's location for a map's showsUserLocation, from Windows' location service
// (Windows.Devices.Geolocation's Geolocator).
//
// One Geolocator for the process, shared by every map that shows the location: it is started when the
// first map starts listening and stopped when the last one stops, so Windows' location indicator (in
// the taskbar) is on only while a map shows the location. A map that starts listening while a position
// is known gets it at once. Windows asks the user the first time a program wants the location, and its
// Settings (Privacy & security, Location) can turn the location off for every program or for desktop
// programs; then there is no position, and the status says why.

#include "ShimInternal.h"

#include <map>
#include <string>
#include <utility>

#include <winrt/Windows.Devices.Geolocation.h>

namespace actionui_winui {

namespace {

namespace geo = winrt::Windows::Devices::Geolocation;

struct LocationState {
    std::map<int, LocationListener> listeners;
    int nextToken = 1;
    // Counts the starts: what comes back for one stopped since finds a newer count.
    int generation = 0;
    dispatching::DispatcherQueue queue{nullptr};
    geo::Geolocator locator{nullptr};
    winrt::event_token positionToken{};
    winrt::event_token statusToken{};
    bool hasLatest = false;
    double latitude = 0;
    double longitude = 0;
    std::string status = "off";
};

LocationState &state() {
    static auto *shared = new LocationState();
    return *shared;
}

// Sends a position to every listener (a copy of them: a listener may stop listening).
void deliver(int generation, double latitude, double longitude) {
    LocationState &s = state();
    if (generation != s.generation || s.listeners.empty()) {
        return;
    }
    s.hasLatest = true;
    s.latitude = latitude;
    s.longitude = longitude;
    s.status = "running";
    std::map<int, LocationListener> listeners = s.listeners;
    for (auto &entry : listeners) {
        // One map failing does not keep the position from the others.
        try {
            entry.second(latitude, longitude);
        } catch (...) {
        }
    }
}

void statusChanged(int generation, geo::PositionStatus status) {
    LocationState &s = state();
    if (generation != s.generation) {
        return;
    }
    switch (status) {
    case geo::PositionStatus::Ready:
        s.status = s.hasLatest ? "running" : "waiting for a position";
        break;
    case geo::PositionStatus::Initializing:
    case geo::PositionStatus::NoData:
        s.status = "waiting for a position";
        break;
    case geo::PositionStatus::Disabled:
        s.status = "off: Windows' location (Settings, Privacy & security, Location) is off for this program";
        break;
    case geo::PositionStatus::NotAvailable:
        s.status = "not available on this computer";
        break;
    default:
        s.status = "not available";
        break;
    }
}

// Asks Windows for the location (it may ask the user), then listens. Resumes on the UI thread.
winrt::fire_and_forget start(int generation) {
    std::string failure;
    try {
        geo::GeolocationAccessStatus access = co_await geo::Geolocator::RequestAccessAsync();
        LocationState &s = state();
        if (generation != s.generation || s.listeners.empty()) {
            co_return;
        }
        if (access != geo::GeolocationAccessStatus::Allowed) {
            s.status = access == geo::GeolocationAccessStatus::Denied
                           ? "denied: Windows' location (Settings, Privacy & security, Location) is off for this program"
                           : "not allowed: Windows did not say whether this program may use the location";
            co_return;
        }
        geo::Geolocator locator;
        // A new position when the user has moved a few meters, at most every second.
        locator.MovementThreshold(5);
        locator.ReportInterval(1000);
        dispatching::DispatcherQueue queue = s.queue;
        // Raised on other threads: what they read goes to the UI thread, and nothing leaves them. The
        // status first: the position's handler starts the service, whose first status (Disabled,
        // NotAvailable) may come at once.
        s.statusToken = locator.StatusChanged([queue, generation](geo::Geolocator const &, geo::StatusChangedEventArgs const &args) {
            try {
                geo::PositionStatus status = args.Status();
                queue.TryEnqueue([generation, status]() {
                    try {
                        statusChanged(generation, status);
                    } catch (...) {
                    }
                });
            } catch (...) {
            }
        });
        s.positionToken = locator.PositionChanged([queue, generation](geo::Geolocator const &, geo::PositionChangedEventArgs const &args) {
            try {
                geo::BasicGeoposition point = args.Position().Coordinate().Point().Position();
                double latitude = point.Latitude;
                double longitude = point.Longitude;
                queue.TryEnqueue([generation, latitude, longitude]() {
                    try {
                        deliver(generation, latitude, longitude);
                    } catch (...) {
                    }
                });
            } catch (...) {
            }
        });
        s.locator = locator;
        s.status = "waiting for a position";
    } catch (winrt::hresult_error const &error) {
        failure = winrt::to_string(error.message());
        if (failure.empty()) {
            failure = "the location service could not start";
        }
    } catch (std::exception const &error) {
        failure = error.what();
    } catch (...) {
        failure = "an unknown C++ exception";
    }
    if (!failure.empty()) {
        try {
            LocationState &s = state();
            if (generation == s.generation) {
                s.status = "not available: " + failure;
            }
        } catch (...) {
        }
    }
}

void stopLocator() {
    LocationState &s = state();
    s.generation += 1;
    if (s.locator != nullptr) {
        s.locator.PositionChanged(s.positionToken);
        s.locator.StatusChanged(s.statusToken);
        s.locator = nullptr;
    }
    s.hasLatest = false;
    s.status = "off";
}

} // namespace

int locationListen(LocationListener listener) {
    LocationState &s = state();
    // Before the listener is added: off the UI thread this throws, and a listener nobody holds the
    // token of would keep the service running.
    dispatching::DispatcherQueue queue = currentQueue();
    int token = s.nextToken++;
    s.listeners.emplace(token, std::move(listener));
    if (s.listeners.size() == 1) {
        s.queue = queue;
        s.generation += 1;
        s.status = "asking Windows";
        start(s.generation);
    } else if (s.hasLatest) {
        // Not out of here: the caller would not get the token to stop with.
        try {
            s.listeners[token](s.latitude, s.longitude);
        } catch (...) {
        }
    }
    return token;
}

void locationStop(int token) {
    LocationState &s = state();
    if (s.listeners.erase(token) != 0 && s.listeners.empty()) {
        stopLocator();
    }
}

std::string locationStatus() {
    return state().status;
}

} // namespace actionui_winui
