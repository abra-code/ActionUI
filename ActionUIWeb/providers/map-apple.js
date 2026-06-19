// map-apple.js — the opt-in Apple MapKit JS provider for the `Map` element.
// The web twin of Apple's native MapKit Map (ActionUI/Views/Map.swift) and the
// closest the web gets to platform parity on Apple devices: a richer provider a
// developer LINKS to override the dependency-free embed default (Views/MapEmbed.js).
// On the web "linking" is importing this ES module AFTER ActionUI.js:
//
//   import { Application, Window } from ".../src/ActionUI.js";
//   import ".../providers/map-apple.js";   // registers "Map", overriding the default
//
// It is NOT imported by core — MapKit JS (and its Apple-Developer token baggage)
// only enters a page that opts in, preserving the dependency-free, no-build-step
// core. register("Map", ...) runs last and wins, the same "swap the module" choice
// as Android (:map-osm vs :map-google). Built on the SAME template as
// providers/map-maplibre.js / map-google.js — same contract, same value bridge —
// differing only in the underlying library's API.
//
// Of the three rich providers this is the cleanest fit for the contract: MapKit JS
// has per-mode interaction toggles (isScrollEnabled / isZoomEnabled /
// isRotationEnabled — an exact match for interactionModes, no best-effort) and a
// built-in user-location dot (showsUserLocation), so it mirrors the native Map most
// faithfully. The provider-independent contract (validation + the coordinate value
// bridge) lives in src/Helpers/MapContract.js.
//
// Token + terms. MapKit JS requires a JWT signed with an Apple Developer MapKit key
// (Apple Developer Program, see ActionUIWeb_Map_Options.md 4e) — which is exactly
// why it is an opt-in module, never a default. Supply it with token:web (a static
// JWT) or tokenURL:web (an endpoint returning a fresh JWT, Apple's recommended
// short-lived-token path; MapKit re-invokes it on expiry), or set a page-wide
// fallback via window.AUI_MAPKIT_JS_TOKEN (handy for the demo). MapKit initializes
// ONCE per page (mapkit.init), so the token config of the FIRST Map built wins for
// the page. The library is lazy-loaded from Apple's CDN (libraryURL:web overrides).
// Like every greedy media element it fills the offered frame; bound its height with
// a frame in an unbounded scroll column.

import { register } from "../src/Common/ActionUIRegistry.js";
import {
    resolveMapConfig,
    mapInitialCoordinate,
    coordinateToValueString,
    parseCoordinateValueString,
    coordinatesEqual,
} from "../src/Helpers/MapContract.js";

// Apple's CDN loader. "5.x.x" is Apple's own literal placeholder — the CDN resolves
// it to the latest MapKit JS 5 release. libraryURL:web overrides it (e.g. to pin a
// version). The classic mapkit.js bundles every library (map + annotations).
const DEFAULT_LIBRARY = "https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js";
// Visible-region span (degrees) for the initial framing, matching the embed/MapLibre
// ~0.1deg view so a single pin frames consistently across providers.
const SPAN = 0.1;

let libraryPromise = null;

// Lazy-loads MapKit JS once and runs mapkit.init with the host's authorization
// callback, resolving to window.mapkit. Memoized so every Map on the page shares one
// load + one init (MapKit is a page-global singleton). `authorize` is MapKit's
// authorizationCallback: (done) => done(jwt) — re-invoked by MapKit on token expiry.
function loadMapKit(authorize, libraryURL) {
    if (libraryPromise) return libraryPromise;
    libraryPromise = new Promise((resolve, reject) => {
        const init = () => {
            try {
                window.mapkit.init({ authorizationCallback: authorize });
                resolve(window.mapkit);
            } catch (error) {
                reject(error);
            }
        };
        if (window.mapkit) { init(); return; }
        const script = document.createElement("script");
        script.src = libraryURL || DEFAULT_LIBRARY;
        script.crossOrigin = "anonymous";
        script.async = true;
        script.onload = () => {
            if (window.mapkit) init();
            else reject(new Error("MapKit JS loaded but window.mapkit is undefined"));
        };
        script.onerror = () => reject(new Error(`Failed to load MapKit JS from ${script.src}`));
        document.head.appendChild(script);
    });
    return libraryPromise;
}

// Builds MapKit's authorizationCallback from the host's token config. tokenURL:web
// (an endpoint returning a fresh JWT) is preferred — Apple recommends short-lived
// tokens and re-invokes the callback on expiry; token:web is a static JWT. Returns
// null when neither is supplied (the build then logs a clear error).
function makeAuthorize(token, tokenURL) {
    if (tokenURL) {
        return (done) => {
            fetch(tokenURL)
                .then((response) => response.text())
                .then((jwt) => done(jwt.trim()))
                .catch((error) => console.error("MapKit token fetch failed:", error));
        };
    }
    if (token) return (done) => done(token);
    return null;
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
        // told apart from our own region-change report-back (the lastTracked echo
        // guard, the OsmMapView / WebView lastTrackedURL pattern).
        let lastTracked = start;
        let map = null;

        const token = (typeof properties.token === "string" && properties.token)
            || (typeof window !== "undefined" ? window.AUI_MAPKIT_JS_TOKEN : null);
        const tokenURL = typeof properties.tokenURL === "string" ? properties.tokenURL : null;
        const authorize = makeAuthorize(token, tokenURL);

        if (!authorize) {
            ctx.logger.log("Map (Apple): MapKit JS needs a token; set token:web or tokenURL:web on the Map (or window.AUI_MAPKIT_JS_TOKEN)", "error");
        } else {
            loadMapKit(authorize, properties.libraryURL)
                .then((mapkit) => {
                    map = new mapkit.Map(node, {
                        showsUserLocation: config.showsUserLocation,
                        // Per-mode interaction toggles — an exact match for the
                        // contract's interactionModes (no best-effort needed).
                        isScrollEnabled: config.interactionModes.includes("pan"),
                        isZoomEnabled: config.interactionModes.includes("zoom"),
                        isRotationEnabled: config.interactionModes.includes("rotate"),
                    });
                    map.region = new mapkit.CoordinateRegion(
                        new mapkit.Coordinate(start.latitude, start.longitude),
                        new mapkit.CoordinateSpan(SPAN, SPAN),
                    );

                    for (const annotation of config.annotations) {
                        // MapKit's MarkerAnnotation renders title/subtitle as plain
                        // text in its native callout (no markup), so there is nothing
                        // to escape — the analog of MapLibre's setDOMContent guard.
                        const marker = new mapkit.MarkerAnnotation(
                            new mapkit.Coordinate(annotation.coordinate.latitude, annotation.coordinate.longitude),
                            { title: annotation.title || "", subtitle: annotation.subtitle || "" },
                        );
                        map.addAnnotation(marker);
                    }

                    // Value bridge: region-change-end fires after the visible region
                    // settles from any change (MapKit's moveend/idle analog — user OR
                    // programmatic, so the lastTracked guard drops the host-write
                    // echo). A user pan reports the new center back and fires
                    // valueChangeActionID (only on an actual change); the plain
                    // actionID fires on every settle (Apple's onMapCameraChange .onEnd).
                    map.addEventListener("region-change-end", () => {
                        const c = map.center; // mapkit.Coordinate: .latitude / .longitude
                        const coordinate = { latitude: c.latitude, longitude: c.longitude };
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
                .catch((error) => ctx.logger.log(`Map (Apple): ${error.message}`, "error"));
        }

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
                    // Setting .center jumps (no animation) so the echoing
                    // region-change-end lands on lastTracked and the guard drops it.
                    if (map) map.center = new window.mapkit.Coordinate(coordinate.latitude, coordinate.longitude);
                },
            });
        }

        node._auiDestroy = () => { if (map) map.destroy(); };
        return node;
    },
});
