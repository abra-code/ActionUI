// VideoPlayer.js — VideoPlayer element.
// Web analog of ActionUI/Views/VideoPlayer.swift (AVKit VideoPlayer) and
// ActionUIAndroid Views/VideoPlayer.kt (a native VideoView + MediaController).
//
// The OS ships a video element with transport controls, so this is a native
// <video controls> - no media library (the WebView / AsyncImage stance: prefer
// the platform's own element over a dependency).
//
// Properties (VideoPlayer.swift):
//   url       String, required. Missing/empty -> an error row replaces the
//             player (Apple's Label("Missing or invalid URL", systemImage
//             "exclamationmark.triangle")). A present-but-unloadable URL is a
//             runtime failure: the <video> error event logs it (Android's
//             onErrorListener), the player just shows nothing playable.
//   autoplay  Bool tri-state: true plays on load, false/absent rest. See the
//             browser-policy note below.
// Baseline View modifiers (frame, cornerRadius, ...) are applied by the registry
// after buildView; a video player is greedy (fills its frame), so bound its
// height with a frame when in a scroll column.
//
// Browser autoplay policy (a documented divergence from Apple/Android): browsers
// refuse autoplay-with-sound until the user has interacted with the page, so
// `autoplay: true` additionally MUTES the element - muted autoplay is the only
// autoplay the browser will honor unprompted. (See Web_Porting_Notes.)
//
// Value bridge (Apple's, valueType "string"): the runtime value is the video
// URL; a host setString swaps the source and reloads. The element never writes
// back (playback position is not observable on the Apple side either).

import { register } from "../Common/ActionUIRegistry.js";
import { systemSymbolGlyph } from "../Helpers/SymbolIcon.js";

register("VideoPlayer", {
    valueType: "string",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.url !== undefined && typeof validated.url !== "string") {
            logger.log(`VideoPlayer url must be a String; ignoring`, "error");
            delete validated.url;
        }
        if (validated.autoplay !== undefined && typeof validated.autoplay !== "boolean") {
            logger.log(`Invalid type for VideoPlayer autoplay: expected Bool, ignoring`, "warning");
            delete validated.autoplay;
        }
        return validated;
    },

    // The static value is the url (default "", Apple parity); a host setString
    // overrides it.
    initialValue: (element, properties) => properties.url ?? "",

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-video-player";

        const autoplay = properties.autoplay === true;
        render(node, properties.url, autoplay, ctx);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => node.dataset.auiUrl ?? "",
                setValue: (value) => render(node, value, autoplay, ctx),
            });
        }
        return node;
    },
});

// Renders `url` into `node`: a native <video controls>, or - when the URL is
// missing/empty - the Apple error row (a warning glyph + message).
function render(node, url, autoplay, ctx) {
    node.replaceChildren();
    node.dataset.auiUrl = typeof url === "string" ? url : "";

    if (typeof url !== "string" || url.trim().length === 0) {
        ctx.logger.log(`VideoPlayer missing or invalid URL, displaying error Label`, "error");
        node.appendChild(errorRow(ctx));
        return;
    }

    const video = document.createElement("video");
    video.controls = true;
    video.style.width = "100%";
    video.style.height = "100%";
    // A present-but-unloadable URL is a runtime failure (Android's
    // onErrorListener), not a build error: log it, no crash.
    video.addEventListener("error", () => {
        ctx.logger.log(`VideoPlayer failed to load '${url}'`, "error");
    });
    if (autoplay) {
        // Muted is the only autoplay the browser honors unprompted (see header).
        video.muted = true;
        video.autoplay = true;
    } else {
        video.preload = "metadata"; // show the first frame, not a black box
    }
    video.src = url;
    node.appendChild(video);
}

// Apple's Label("Missing or invalid URL", systemImage "exclamationmark.triangle").
function errorRow(ctx) {
    const row = document.createElement("span");
    row.className = "aui-video-error";
    row.appendChild(systemSymbolGlyph("exclamationmark.triangle", {}, ctx.logger, (n) =>
        `VideoPlayer error glyph '${n}' has no SF->Material mapping.`));
    const text = document.createElement("span");
    text.textContent = "Missing or invalid URL";
    row.appendChild(text);
    return row;
}
