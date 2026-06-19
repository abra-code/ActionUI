// map-maplibre.js — the opt-in MapLibre GL JS provider for the `Map` element.
// The web twin of Android's :map-google module: a richer provider a developer
// LINKS to override the dependency-free embed default (Views/MapEmbed.js). On the
// web "linking" is importing this ES module AFTER ActionUI.js:
//
//   import { Application, Window } from ".../src/ActionUI.js";
//   import ".../providers/map-maplibre.js";   // registers "Map", overriding the default
//
// It is NOT imported by core — the MapLibre library (and its tile/style/key terms)
// only enters a page that actually opts in, preserving the dependency-free,
// no-build-step core. register("Map", ...) runs last and wins, the same "swap the
// module" choice as Android (:map-osm vs :map-google) or Apple (native MapKit).
//
// Mirror of ActionUI/Views/Map.swift (MapKit) and Android's OsmMapView.kt: the full
// contract, not the embed's display-only subset — programmatic center, annotation
// markers with title/subtitle popups, interactionModes, and the user-pan value
// bridge (moveend -> report center + fire valueChangeActionID), which an opaque
// embed cannot do (decision-doc "mechanism A"). The provider-independent contract
// (validation + the coordinate value bridge) lives in src/Helpers/MapContract.js.
//
// Library + tiles. MapLibre GL JS (BSD-3) is lazy-loaded from a CDN on first build
// (libraryURL:web overrides). The map STYLE (tiles) is the host's choice and terms:
// supply styleURL:web pointing at your own keyed/self-hosted style; absent one, it
// falls back to MapLibre's key-free demo style (demo tiles only — not for
// production). Like every greedy media element it fills the offered frame; bound
// its height with a frame in an unbounded scroll column.

import { register } from "../src/Common/ActionUIRegistry.js";
import {
    resolveMapConfig,
    mapInitialCoordinate,
    coordinateToValueString,
    parseCoordinateValueString,
    coordinatesEqual,
} from "../src/Helpers/MapContract.js";

const DEFAULT_LIBRARY_JS = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js";
const DEFAULT_LIBRARY_CSS = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css";
// MapLibre's key-free demo style. Documented as demo-only; a real deployment sets
// styleURL:web to its own keyed/self-hosted style (see ActionUIWeb_Map_Options.md).
const DEFAULT_STYLE_URL = "https://demotiles.maplibre.org/style.json";

let libraryPromise = null;

// Lazy-loads MapLibre GL JS + CSS once, resolving to window.maplibregl. Memoized so
// every Map on the page shares one load. A CDN fetch is a network dependency the
// opt-in accepts (a host self-hosts by setting libraryURL:web / shipping the CSS).
function loadMapLibre(libraryURL, cssURL) {
    if (libraryPromise) return libraryPromise;
    libraryPromise = new Promise((resolve, reject) => {
        if (window.maplibregl) {
            resolve(window.maplibregl);
            return;
        }
        const link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = cssURL || DEFAULT_LIBRARY_CSS;
        document.head.appendChild(link);

        const script = document.createElement("script");
        script.src = libraryURL || DEFAULT_LIBRARY_JS;
        script.async = true;
        script.onload = () => {
            if (window.maplibregl) resolve(window.maplibregl);
            else reject(new Error("MapLibre loaded but window.maplibregl is undefined"));
        };
        script.onerror = () => reject(new Error(`Failed to load MapLibre from ${script.src}`));
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

        const start = parseCoordinateValueString(coordinateToValueString(config.coordinate ?? mapInitialCoordinate(properties)));
        let currentValue = coordinateToValueString(start);
        // The last center this element reported into itself, so a host write can be
        // told apart from our own moveend report-back (OsmMapView's lastTracked /
        // WebView's lastTrackedURL pattern).
        let lastTracked = start;
        let map = null;

        const styleURL = typeof properties.styleURL === "string" ? properties.styleURL : DEFAULT_STYLE_URL;

        loadMapLibre(properties.libraryURL, properties.libraryCSSURL)
            .then((maplibregl) => {
                map = new maplibregl.Map({
                    container: node,
                    style: styleURL,
                    center: [start.longitude, start.latitude],
                    zoom: 10,
                    attributionControl: true, // required by every tile provider's ToS
                });
                applyInteractionModes(map, config.interactionModes);

                for (const annotation of config.annotations) {
                    const marker = new maplibregl.Marker()
                        .setLngLat([annotation.coordinate.longitude, annotation.coordinate.latitude])
                        .addTo(map);
                    const popup = annotationPopup(maplibregl, annotation);
                    if (popup) marker.setPopup(popup);
                }

                if (config.showsUserLocation) {
                    map.addControl(new maplibregl.GeolocateControl({ trackUserLocation: false }));
                }

                // Value bridge: a user pan reports the new center back and fires
                // valueChangeActionID (only on an actual change); the plain actionID
                // fires on every camera-change end (Apple's onMapCameraChange .onEnd).
                map.on("moveend", () => {
                    const c = map.getCenter();
                    const coordinate = { latitude: c.lat, longitude: c.lng };
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
            .catch((error) => ctx.logger.log(`Map (MapLibre): ${error.message}`, "error"));

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
                    // jumpTo (not flyTo) so the echoing moveend lands on lastTracked
                    // and the guard above drops it — no spurious valueChange.
                    if (map) map.jumpTo({ center: [coordinate.longitude, coordinate.latitude] });
                },
            });
        }

        node._auiDestroy = () => { if (map) map.remove(); };
        return node;
    },
});

// pan -> dragPan + touch drag; zoom -> scroll/dblclick/box/keyboard zoom;
// rotate -> dragRotate + touch rotate. Disable the modes not requested.
function applyInteractionModes(map, modes) {
    if (!modes.includes("pan")) map.dragPan.disable();
    if (!modes.includes("zoom")) {
        map.scrollZoom.disable();
        map.doubleClickZoom.disable();
        map.boxZoom.disable();
        map.keyboard.disable();
    }
    if (!modes.includes("rotate")) {
        map.dragRotate.disable();
        map.touchZoomRotate.disableRotation();
    }
}

// A popup with the title bold over the subtitle, built as DOM (textContent, never
// HTML) so annotation text cannot inject markup — the safe analog of OsmMapView's
// escapeForPopup. Returns null when there is nothing to show.
function annotationPopup(maplibregl, annotation) {
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
    return new maplibregl.Popup({ offset: 24 }).setDOMContent(content);
}
