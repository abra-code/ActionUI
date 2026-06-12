// ScrollView.js — ScrollView element.
// Web analog of ActionUI/Views/ScrollView.swift (and ActionUIAndroid Views/ScrollView.kt).
//
// A scrolling viewport around a single child, supplied under the top-level
// `content` key (the single-child named container, already routed by
// ActionUIElement) — not `children`. Rendered as a `<div>` with CSS `overflow`
// on the scrolling axis; the child overflows and scrolls. To actually scroll,
// the viewport needs a bounded extent on the scroll axis — give it a `frame`
// (e.g. `maxHeight`) via the baseline modifiers.
//
// Properties (mirroring ScrollView.swift):
//   axis             "vertical" (default), "horizontal", or "both".
//   showsIndicators  Boolean (default true); when false the scrollbars are
//                    hidden (scrollbar-width / ::-webkit-scrollbar), the web
//                    counterpart of SwiftUI's .scrollIndicators(.hidden).

import { register } from "../Common/ActionUIRegistry.js";

// Maps the JSON axis to the pair of CSS overflow values [overflowY, overflowX].
const OVERFLOW_FOR_AXIS = {
    vertical: ["auto", "hidden"],
    horizontal: ["hidden", "auto"],
    both: ["auto", "auto"],
};

register("ScrollView", {
    valueType: "none",

    // Mirrors ScrollView.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (typeof validated.axis === "string" && !["vertical", "horizontal", "both"].includes(validated.axis)) {
            logger.log(`ScrollView axis '${validated.axis}' invalid; defaulting to 'vertical'`, "warning");
            validated.axis = "vertical";
        }

        if (validated.showsIndicators === undefined) {
            validated.showsIndicators = true;
        } else if (typeof validated.showsIndicators === "boolean") {
            // keep as-is
        } else {
            logger.log("ScrollView showsIndicators must be a Boolean; defaulting to true", "warning");
            validated.showsIndicators = true;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-scroll";

        const axis = typeof properties.axis === "string" ? properties.axis : "vertical";
        const [overflowY, overflowX] = OVERFLOW_FOR_AXIS[axis] ?? OVERFLOW_FOR_AXIS.vertical;
        node.style.overflowY = overflowY;
        node.style.overflowX = overflowX;

        // showsIndicators false → hide the scrollbars (the .scrollIndicators(.hidden) analog).
        if (properties.showsIndicators === false) {
            node.classList.add("aui-scroll-no-indicators");
        }

        const content = element.subviews?.content;
        if (content) {
            node.appendChild(ctx.build(content));
        }
        return node;
    },
});
