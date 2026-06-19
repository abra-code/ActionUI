// ShareLink.js — ShareLink element.
// Web analog of ActionUI/Views/ShareLink.swift (SwiftUI.ShareLink, the system
// share sheet) and ActionUIAndroid Views/ShareLink.kt (Intent(ACTION_SEND)).
//
// Renders the system share affordance: a borderless button (the share glyph +
// "Share") that invokes the Web Share API (navigator.share) - the browser's own
// share sheet, the analog of Apple's share sheet / Android's ACTION_SEND chooser.
// A missing/invalid item renders nothing (the Swift/Android EmptyView fallback,
// same warning).
//
// Properties (ShareLink.swift): item (String url), subject (String), message
// (String). subject -> the share title, message -> the share text, item -> url.
//
// Divergences (Web_Porting_Notes.md):
//   * navigator.share requires a user gesture (the click satisfies it) and a
//     secure context (https / localhost). When it is unavailable (older browser
//     or insecure origin) the button falls back to copying the item to the
//     clipboard (navigator.clipboard) and logging - a graceful degrade, not a
//     crash. A user-cancelled share (AbortError) is swallowed silently.
//   * item validity is "a non-empty String" (the browser handles the URL);
//     type validation stays verbatim Swift.

import { register } from "../Common/ActionUIRegistry.js";
import { systemSymbolGlyph } from "../Helpers/SymbolIcon.js";

register("ShareLink", {
    valueType: "none",

    // Mirrors ShareLink.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (typeof validated.item === "string") {
            if (validated.item.trim().length === 0) {
                logger.log(`Invalid ShareLink item '${validated.item}', ignoring`, "warning");
                delete validated.item;
            }
        } else if (validated.item !== undefined) {
            logger.log(`Invalid type for ShareLink item: expected String, got ${typeof validated.item}, ignoring`, "warning");
            delete validated.item;
        }

        if (validated.subject !== undefined && typeof validated.subject !== "string") {
            logger.log(`Invalid type for ShareLink subject: expected String, got ${typeof validated.subject}, ignoring`, "warning");
            delete validated.subject;
        }

        if (validated.message !== undefined && typeof validated.message !== "string") {
            logger.log(`Invalid type for ShareLink message: expected String, got ${typeof validated.message}, ignoring`, "warning");
            delete validated.message;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const item = typeof properties.item === "string" ? properties.item.trim() : "";
        if (item.length === 0) {
            ctx.logger.log("ShareLink missing valid URL, returning EmptyView", "warning");
            const empty = document.createElement("div");
            empty.className = "aui-empty";
            return empty;
        }

        const subject = typeof properties.subject === "string" ? properties.subject : undefined;
        const message = typeof properties.message === "string" ? properties.message : undefined;

        const node = document.createElement("button");
        node.className = "aui-sharelink";
        node.appendChild(systemSymbolGlyph("square.and.arrow.up", {}, ctx.logger, (n) =>
            `ShareLink glyph '${n}' has no SF->Material mapping.`));
        const label = document.createElement("span");
        label.textContent = "Share";
        node.appendChild(label);

        node.addEventListener("click", () => share(item, subject, message, ctx.logger));
        return node;
    },
});

// Invokes the Web Share API, falling back to the clipboard when it is unavailable.
function share(url, subject, message, logger) {
    const data = { url };
    if (subject !== undefined) data.title = subject;
    if (message !== undefined) data.text = message;

    if (typeof navigator.share === "function") {
        navigator.share(data).catch((err) => {
            // A user-cancelled share is not an error worth surfacing.
            if (err && err.name === "AbortError") return;
            logger.log(`ShareLink share failed (${err && err.name ? err.name : "error"}); ` +
                `copying the link to the clipboard instead.`, "warning");
            copyToClipboard(url, logger);
        });
        return;
    }
    logger.log("ShareLink: Web Share API unavailable (needs a secure context); " +
        "copying the link to the clipboard instead.", "warning");
    copyToClipboard(url, logger);
}

function copyToClipboard(text, logger) {
    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
        navigator.clipboard.writeText(text).catch((err) => {
            logger.log(`ShareLink clipboard copy failed: ${err}`, "warning");
        });
    } else {
        logger.log("ShareLink: clipboard unavailable; nothing shared.", "warning");
    }
}
