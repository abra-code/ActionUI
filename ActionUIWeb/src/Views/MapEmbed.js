// MapEmbed.js — the default, dependency-free `Map` provider.
// Web analog of ActionUI/Views/Map.swift (MapKit) and the Android :map-osm module,
// but deliberately the lightest possible rendering: a display-only OpenStreetMap
// embed (a plain <iframe>, no JS map library, no key) plus a platform-aware
// "Open in Maps" handoff that opens the location in the visitor's native maps app.
// Canonical schema: Documentation/Schemas/Map.md; the provider-independent contract
// (validation + the coordinate value bridge) lives in Helpers/MapContract.js.
//
// PLUGGABLE BY DESIGN. Map is the Android "link exactly one provider" model. This
// default ships in core (ActionUI.js imports it) — a deliberate divergence from
// Android's "core ships nothing map-related", justified because the embed has ZERO
// third-party dependency, so the web has a working Map out of the box. Importing a
// richer provider module (providers/map-maplibre.js, ...) AFTER ActionUI.js calls
// register("Map", ...) again and overrides this one (last registration wins) — the
// same "swap the module" choice a developer makes on Android (:map-osm vs
// :map-google) or Apple (native MapKit). Provider config rides on :web-suffixed
// keys (openInMapsURL:web) so the shared document stays clean.
//
// Value bridge (valueType "string"): the value is the center as a JSON coordinate
// string. A host setString re-centers (we own the iframe src and rebuild it).
//
// Divergences, all inherent to a display-only embed (decision-doc "mechanism B":
// an iframe is opaque — no marker API, no center read-back). Documented in
// Web_Porting_Notes.md (Map):
//   * USER PANS DO NOT REPORT BACK — there is no way to read an embed's center —
//     so valueChangeActionID and the camera-change actionID never fire from this
//     default. The host->view direction (re-center) works; the view->host
//     direction does not. The MapLibre provider (a real JS map) restores both.
//   * At most ONE pin: the OSM embed supports a single `marker`, placed at the
//     first annotation. Multiple annotations need a JS provider.
//   * showsUserLocation is accepted but not rendered; interactionModes are
//     accepted but governed by the embed's own UI (no per-mode toggle).
//   * Like every greedy media element it fills the frame the parent offers; bound
//     its height with a frame in an unbounded scroll column (the bounded-height
//     caveat shared with WebView/Canvas).

import { register } from "../Common/ActionUIRegistry.js";
import {
    resolveMapConfig,
    mapInitialCoordinate,
    coordinateToValueString,
    parseCoordinateValueString,
} from "../Helpers/MapContract.js";

// Half the ~0.1-degree span Apple's Map uses, so the bbox brackets the center.
const HALF_SPAN = 0.05;

register("Map", {
    valueType: "string",

    // All Map validation/warnings happen once in resolveMapConfig at build time
    // ("validate where you read"); modifiers (frame, cornerRadius, ...) pass through.
    validateProperties: (properties) => properties ?? {},

    initialValue: (element, properties) => coordinateToValueString(mapInitialCoordinate(properties)),

    buildView: (element, properties, ctx) => {
        const config = resolveMapConfig(properties, ctx.logger);

        const node = document.createElement("div");
        node.className = "aui-map";

        const frame = document.createElement("iframe");
        frame.className = "aui-map-frame";
        frame.setAttribute("referrerpolicy", "no-referrer");
        frame.setAttribute("loading", "lazy");
        frame.setAttribute("title", "Map");
        node.appendChild(frame);

        const open = document.createElement("a");
        open.className = "aui-map-open";
        open.target = "_blank";
        open.rel = "noopener";
        open.textContent = "Open in Maps";
        node.appendChild(open);

        // The marker (and the handoff label) come from the first annotation, if
        // any; the center is the coordinate, else the first annotation, else 0,0.
        const firstAnnotation = config.annotations[0] ?? null;
        const center = config.coordinate ?? firstAnnotation?.coordinate ?? { latitude: 0.0, longitude: 0.0 };
        const label = firstAnnotation?.title ?? null;
        const openURLTemplate = typeof properties.openInMapsURL === "string" ? properties.openInMapsURL : null;

        let currentValue = coordinateToValueString(center);

        const render = (coordinate) => {
            frame.src = embedURL(coordinate, firstAnnotation?.coordinate ?? null);
            open.href = openInMapsURL(coordinate, label, openURLTemplate);
        };
        render(center);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => currentValue,
                setValue: (value) => {
                    const coordinate = parseCoordinateValueString(String(value ?? ""));
                    if (!coordinate) {
                        ctx.logger.log("Map: failed to parse coordinate JSON string", "warning");
                        return;
                    }
                    currentValue = coordinateToValueString(coordinate);
                    render(coordinate);
                },
            });
        }

        return node;
    },
});

// The OpenStreetMap export embed: a bbox bracketing the center (~0.1deg span) plus
// an optional single marker. Key-free and dependency-free, display-only. The query
// is built with literal commas (RFC 3986 sub-delims, the conventional embed URL
// shape) rather than URLSearchParams, which would percent-encode them.
function embedURL(center, markerCoordinate) {
    const round = (n) => Number(n.toFixed(6)); // trim float-subtraction noise
    const bbox = [
        round(center.longitude - HALF_SPAN), round(center.latitude - HALF_SPAN),
        round(center.longitude + HALF_SPAN), round(center.latitude + HALF_SPAN),
    ].join(",");
    const marker = markerCoordinate
        ? `&marker=${markerCoordinate.latitude},${markerCoordinate.longitude}`
        : "";
    return `https://www.openstreetmap.org/export/embed.html?bbox=${bbox}&layer=mapnik${marker}`;
}

// The "Open in Maps" handoff. Default is platform-aware: Apple devices ->
// maps.apple.com (deep-links to the Apple Maps app), everything else ->
// google.com/maps (deep-links to the Google Maps app). A host can override with
// openInMapsURL:web — a template whose {latitude}/{longitude}/{lat}/{lon} tokens
// are substituted (a template with no token is used verbatim, a fixed link).
function openInMapsURL(coordinate, label, template) {
    const lat = coordinate.latitude;
    const lon = coordinate.longitude;
    if (template) {
        if (/\{(latitude|longitude|lat|lon)\}/.test(template)) {
            return template
                .replace(/\{latitude\}/g, String(lat))
                .replace(/\{longitude\}/g, String(lon))
                .replace(/\{lat\}/g, String(lat))
                .replace(/\{lon\}/g, String(lon));
        }
        return template;
    }
    if (isApplePlatform()) {
        const q = label ? `&q=${encodeURIComponent(label)}` : "";
        return `https://maps.apple.com/?ll=${lat},${lon}${q}`;
    }
    return `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;
}

// True on Apple devices (iPhone/iPad/iPod/Mac). iPadOS reports as "MacIntel" with
// touch — both branches resolve to Apple Maps, which is correct.
function isApplePlatform() {
    const nav = typeof navigator !== "undefined" ? navigator : null;
    if (!nav) return false;
    const platform = nav.userAgentData?.platform || nav.platform || "";
    const ua = nav.userAgent || "";
    return /Mac|iPhone|iPad|iPod/i.test(platform) || /iPhone|iPad|iPod/i.test(ua);
}
