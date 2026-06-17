// map-google.js — the opt-in Google Maps JavaScript API provider for `Map`.
// The web twin of Android's :map-google module and Apple's option to use Google's
// SDK: a richer provider a developer LINKS to override the dependency-free embed
// default (Views/MapEmbed.js). On the web "linking" is importing this ES module
// AFTER ActionUI.js:
//
//   import { Application, Window } from ".../src/ActionUI.js";
//   import ".../providers/map-google.js";   // registers "Map", overriding the default
//
// It is NOT imported by core — the Google Maps library (and its key/billing/ToS
// baggage) only enters a page that actually opts in, preserving the dependency-free,
// no-build-step core. register("Map", ...) runs last and wins, the same "swap the
// module" choice as Android (:map-osm vs :map-google) or Apple (native MapKit). It
// is built on the same template as providers/map-maplibre.js — same contract, same
// value bridge — differing only in the underlying library's API.
//
// Mirror of ActionUI/Views/Map.swift and Android's :map-google: the full contract,
// not the embed's display-only subset — programmatic center, annotation markers with
// title/subtitle InfoWindows, interactionModes, and the user-pan value bridge
// (idle -> report center + fire valueChangeActionID), which an opaque embed cannot
// do (decision-doc "mechanism A"). The provider-independent contract (validation +
// the coordinate value bridge) lives in src/Helpers/MapContract.js.
//
// Key + terms. The Google Maps JavaScript API requires the host's own API key and a
// billing account, and its ToS govern caching/attribution (see ActionUIWeb_Map_Options.md
// 4c) — which is exactly why it is an opt-in module, never a default. Supply the key
// with apiKey:web on the Map element, or set a page-wide fallback once via
// window.AUI_GOOGLE_MAPS_API_KEY (handy for the demo). The library is lazy-loaded
// from Google's loader on first build (libraryURL:web overrides the loader endpoint,
// e.g. a regional proxy; mapId:web selects a cloud-styled vector map). Like every
// greedy media element it fills the offered frame; bound its height with a frame in
// an unbounded scroll column.

import { register } from "../src/Common/ActionUIRegistry.js";
import {
    resolveMapConfig,
    mapInitialCoordinate,
    coordinateToValueString,
    parseCoordinateValueString,
    coordinatesEqual,
} from "../src/Helpers/MapContract.js";

// Google's bootstrap loader endpoint. libraryURL:web overrides it (the key/loading/
// callback query is appended either way, so an override only needs to be the base).
const DEFAULT_LOADER = "https://maps.googleapis.com/maps/api/js";
const DEFAULT_ZOOM = 12;

let libraryPromise = null;

// Lazy-loads the Google Maps JS API once, resolving to window.google.maps. Memoized
// so every Map on the page shares one load. Google requires a `callback` for async
// init, so we register a one-shot global and resolve from it. A CDN fetch is a
// network dependency the opt-in accepts; the key (apiKey:web or the global fallback)
// is the host's and must accompany a billing account.
function loadGoogleMaps(apiKey, libraryURL) {
    if (libraryPromise) return libraryPromise;
    libraryPromise = new Promise((resolve, reject) => {
        if (window.google && window.google.maps) {
            resolve(window.google.maps);
            return;
        }
        if (!apiKey && !libraryURL) {
            reject(new Error("Google Maps needs an API key; set apiKey:web on the Map (or window.AUI_GOOGLE_MAPS_API_KEY)"));
            return;
        }
        const callbackName = "__auiGoogleMapsReady";
        window[callbackName] = () => {
            delete window[callbackName];
            if (window.google && window.google.maps) resolve(window.google.maps);
            else reject(new Error("Google Maps loaded but window.google.maps is undefined"));
        };
        const url = new URL(libraryURL || DEFAULT_LOADER);
        if (apiKey) url.searchParams.set("key", apiKey);
        url.searchParams.set("loading", "async");
        url.searchParams.set("callback", callbackName);

        const script = document.createElement("script");
        script.src = url.toString();
        script.async = true;
        script.onerror = () => reject(new Error(`Failed to load Google Maps from ${url.origin}${url.pathname}`));
        document.head.appendChild(script);
    });
    return libraryPromise;
}

register("Map", {
    valueType: "string",
    validateProperties: (properties) => properties ?? {},
    initialValue: (element, properties) => coordinateToValueString(mapInitialCoordinate(properties)),

    buildView: (element, properties, ctx) => {
        const config = resolveMapConfig(properties, ctx.logger);

        const node = document.createElement("div");
        node.className = "aui-map";

        const start = config.coordinate ?? mapInitialCoordinate(properties);
        let currentValue = coordinateToValueString(start);
        // The last center this element reported into itself, so a host write can be
        // told apart from our own idle report-back (the lastTracked echo guard, the
        // OsmMapView / WebView lastTrackedURL pattern).
        let lastTracked = start;
        let map = null;
        const markers = [];

        const apiKey = (typeof properties.apiKey === "string" && properties.apiKey)
            || (typeof window !== "undefined" ? window.AUI_GOOGLE_MAPS_API_KEY : null);
        const mapId = typeof properties.mapId === "string" ? properties.mapId : undefined;

        loadGoogleMaps(apiKey, properties.libraryURL)
            .then((gmaps) => {
                map = new gmaps.Map(node, {
                    center: { lat: start.latitude, lng: start.longitude },
                    zoom: DEFAULT_ZOOM,
                    mapId,
                    ...interactionOptions(config.interactionModes),
                });

                for (const annotation of config.annotations) {
                    const marker = new gmaps.Marker({
                        position: { lat: annotation.coordinate.latitude, lng: annotation.coordinate.longitude },
                        map,
                        title: annotation.title || undefined,
                    });
                    const info = annotationInfoWindow(gmaps, annotation);
                    if (info) marker.addListener("click", () => info.open({ anchor: marker, map }));
                    markers.push(marker);
                }

                if (config.showsUserLocation) addUserLocationMarker(gmaps, map, markers);

                // Value bridge: `idle` fires after the camera settles from any move
                // (Google's equivalent of MapLibre's moveend). A user pan reports the
                // new center back and fires valueChangeActionID (only on an actual
                // change); the plain actionID fires on every settle (Apple's
                // onMapCameraChange .onEnd). Programmatic setCenter also fires idle —
                // the lastTracked guard drops that echo.
                map.addListener("idle", () => {
                    const c = map.getCenter();
                    const coordinate = { latitude: c.lat(), longitude: c.lng() };
                    if (!coordinatesEqual(coordinate, lastTracked)) {
                        lastTracked = coordinate;
                        currentValue = coordinateToValueString(coordinate);
                        if (config.valueChangeActionID) {
                            ctx.model.dispatchAction(config.valueChangeActionID, element.id, 0, null);
                        }
                    }
                    if (config.actionID) ctx.model.dispatchAction(config.actionID, element.id, 0, null);
                });
            })
            .catch((error) => ctx.logger.log(`Map (Google): ${error.message}`, "error"));

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => currentValue,
                setValue: (value) => {
                    const coordinate = parseCoordinateValueString(String(value ?? ""));
                    if (!coordinate) {
                        ctx.logger.log("Map: failed to parse coordinate JSON string", "warning");
                        return;
                    }
                    if (coordinatesEqual(coordinate, lastTracked)) return; // our own report-back
                    lastTracked = coordinate;
                    currentValue = coordinateToValueString(coordinate);
                    // setCenter (not panTo) so the echoing idle lands on lastTracked
                    // and the guard above drops it — no spurious valueChange.
                    if (map) map.setCenter({ lat: coordinate.latitude, lng: coordinate.longitude });
                },
            });
        }

        node._auiDestroy = () => {
            if (!window.google || !window.google.maps) return;
            for (const marker of markers) {
                window.google.maps.event.clearInstanceListeners(marker);
                marker.setMap(null);
            }
            if (map) window.google.maps.event.clearInstanceListeners(map);
        };
        return node;
    },
});

// Maps the contract's interactionModes onto Google's map options. Google's gesture
// model is coarser than Apple's per-mode set, so this is best-effort (documented in
// Web_Porting_Notes): pan -> draggable + gestureHandling; zoom -> scrollwheel /
// double-click / zoom control; rotate -> rotateControl (real rotation/tilt needs a
// vector map, i.e. a mapId:web). gestureHandling is "none" only when neither pan nor
// zoom is wanted, so touch gestures are fully locked out in that case.
function interactionOptions(modes) {
    const wantsPan = modes.includes("pan");
    const wantsZoom = modes.includes("zoom");
    return {
        gestureHandling: wantsPan || wantsZoom ? "auto" : "none",
        draggable: wantsPan,
        scrollwheel: wantsZoom,
        disableDoubleClickZoom: !wantsZoom,
        zoomControl: wantsZoom,
        rotateControl: modes.includes("rotate"),
    };
}

// An InfoWindow with the title bold over the subtitle, built as DOM (textContent,
// never HTML) so annotation text cannot inject markup — the safe analog of
// OsmMapView's escapeForPopup and the MapLibre provider's setDOMContent. Returns
// null when there is nothing to show.
function annotationInfoWindow(gmaps, annotation) {
    if (!annotation.title && !annotation.subtitle) return null;
    const content = document.createElement("div");
    content.className = "aui-map-popup";
    if (annotation.title) {
        const title = document.createElement("div");
        title.className = "aui-map-popup-title";
        title.textContent = annotation.title;
        content.appendChild(title);
    }
    if (annotation.subtitle) {
        const subtitle = document.createElement("div");
        subtitle.className = "aui-map-popup-subtitle";
        subtitle.textContent = annotation.subtitle;
        content.appendChild(subtitle);
    }
    return new gmaps.InfoWindow({ content });
}

// Best-effort showsUserLocation. The Google Maps JS API has no built-in "blue dot"
// (unlike MapLibre's GeolocateControl or the native SDKs), so we drop a one-shot
// marker at the browser geolocation fix. No live tracking or heading. Documented as
// best-effort in Web_Porting_Notes.
function addUserLocationMarker(gmaps, map, markers) {
    if (typeof navigator === "undefined" || !navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition((pos) => {
        const marker = new gmaps.Marker({
            position: { lat: pos.coords.latitude, lng: pos.coords.longitude },
            map,
            title: "Your location",
        });
        markers.push(marker);
    });
}
