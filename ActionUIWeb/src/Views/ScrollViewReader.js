// ScrollViewReader.js — ScrollViewReader element.
// Web analog of ActionUI/Views/ScrollViewReader.swift (and ActionUIAndroid
// Views/ScrollViewReader.kt).
//
// A programmatic-scrolling wrapper around a single child (typically a
// ScrollView), supplied under the top-level `content` key (the single-child
// named container, routed by ActionUIElement) — not `children`.
//
// SwiftUI's ScrollViewReader hands a proxy whose `scrollTo(id)` brings any
// `.id()`-tagged descendant into view inside the enclosing scrollable. The web
// gets that for free from the DOM: `Element.scrollIntoView()` scrolls the
// target's nearest scrollable ancestor until it is visible, and every
// positive-id element already carries a `data-aui-id` attribute (set by the
// registry). So the DOM itself is the ambient id-registry the proxy needs —
// no per-scrollable enrollment machinery (Android needs that because Compose
// has no ambient equivalent and two unrelated scroll primitives; see
// Helpers/ScrollReaderHelper.kt there).
//
// Apple/Android model the scroll target as the `scrollTo` *property* plus a
// runtime host property write (setElementProperty). The web has no
// property-write API, so the target is the element's Int **value**: the
// authored `scrollTo` seeds it (and scrolls once on first layout), and a host
// re-scrolls at runtime with setElementValue(readerID, targetID). Re-sending
// the same id scrolls again (the value bridge always calls setValue), matching
// the Apple/Android "bring row N back after the user scrolls away" behavior.
//
// Properties (mirroring ScrollViewReader.swift):
//   scrollTo  Int element id to scroll to (warn-and-ignore a non-Int, the
//             Apple validator's rule). Becomes the element's initial Int value.
//   anchor    "top" | "center" (default) | "bottom" — where the target lands in
//             the viewport (block start / center / end). A non-string is left
//             alone by the validator and resolves to center at read time (the
//             Apple `as? String` fall-through, silently).

import { register } from "../Common/ActionUIRegistry.js";

// Maps the JSON anchor to the CSS scrollIntoView `block` placement. Anything
// that is not "top"/"bottom" (including a non-string) centers — the Apple
// UnitPoint default.
function anchorToBlock(anchor) {
    switch (anchor) {
        case "top": return "start";
        case "bottom": return "end";
        default: return "center";
    }
}

register("ScrollViewReader", {
    valueType: "int",

    // Mirrors ScrollViewReader.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // scrollTo: an Int is kept; anything else present is warned and dropped.
        if (Number.isInteger(validated.scrollTo)) {
            // keep as-is
        } else if (validated.scrollTo !== undefined) {
            logger.log("ScrollViewReader scrollTo must be an Int; ignoring", "warning");
            delete validated.scrollTo;
        }

        // anchor: a string outside the set warns and defaults to center; a
        // non-string is left as-is (resolved to center at read time, silently).
        if (typeof validated.anchor === "string" && !["top", "center", "bottom"].includes(validated.anchor)) {
            logger.log(`ScrollViewReader anchor '${validated.anchor}' invalid; defaulting to 'center'`, "warning");
            validated.anchor = "center";
        }

        return validated;
    },

    // The authored scrollTo seeds the Int value (undefined ⇒ not seeded).
    initialValue: (element, properties) => properties.scrollTo,

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-scroll-reader";

        const content = element.subviews?.content;
        if (content) {
            node.appendChild(ctx.build(content));
        }

        const block = anchorToBlock(properties.anchor);

        // Scroll the descendant with data-aui-id === targetID into view inside
        // its nearest scrollable ancestor. Deferred to the next frame so it runs
        // after attach/layout (and after any rows the host just set); a missing
        // target warns and is otherwise a no-op (e.g. a not-yet-built row, or a
        // subtree that is still display:none in the demo's preloaded panes).
        const scrollToTarget = (targetID) => {
            if (!Number.isInteger(targetID)) return;
            requestAnimationFrame(() => {
                const target = node.querySelector(`[data-aui-id="${targetID}"]`);
                if (!target) {
                    ctx.logger.log(`ScrollViewReader: no element with id ${targetID} to scroll to`, "warning");
                    return;
                }
                target.scrollIntoView({ block, inline: "nearest", behavior: "smooth" });
            });
        };

        let currentTarget = Number.isInteger(properties.scrollTo) ? properties.scrollTo : null;

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => currentTarget,
                setValue: (value) => {
                    const n = Math.trunc(Number(value));
                    if (Number.isFinite(n)) currentTarget = n;
                    scrollToTarget(currentTarget);
                },
            });
        }

        // Authored scrollTo scrolls once on first layout — SwiftUI's onAppear
        // proxy.scrollTo / Android's first-composition LaunchedEffect.
        if (currentTarget !== null) scrollToTarget(currentTarget);

        return node;
    },
});
