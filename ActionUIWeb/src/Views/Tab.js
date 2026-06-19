// Tab.js — Tab element.
// Web analog of ActionUI/Views/Tab.swift (and ActionUIAndroid Views/Tab.kt).
//
// Not a standalone view: a Tab carries one tab's metadata (title,
// systemImage / assetImage, badge) in `properties` and the tab body under
// `content`, and is only meaningful inside a TabView's `children`. TabView reads
// that metadata and builds the `content` itself, so a Tab is never constructed
// through the registry in normal use. It is registered anyway so a
// cross-platform document resolves the type; built standalone (misuse) it
// renders nothing and warns — Apple returns EmptyView(), Android no-ops.

import { register } from "../Common/ActionUIRegistry.js";

register("Tab", {
    valueType: "none",
    validateProperties: (properties) => properties,
    buildView: (element, properties, ctx) => {
        ctx.logger.log("Tab is only meaningful inside a TabView; nothing is rendered standalone", "warning");
        const node = document.createElement("div");
        node.className = "aui-tab-standalone";
        node.style.display = "none";
        return node;
    },
});

// A tab's label, defaulting to "Tab N" (Apple's `Tab \(index + 1)` fallback;
// Android defaults to a bare "Tab"). The web follows Apple's indexed form.
export function tabTitle(tab, index) {
    const title = tab.properties?.title;
    return typeof title === "string" ? title : `Tab ${index + 1}`;
}

// A tab's badge text, or null when there is none: an Integer renders as the
// number (clamped to "99+" above 99), a non-empty String renders as itself, an
// empty String or any other type yields no badge. Mirrors Apple's badgeText /
// applyBadge helper.
export function tabBadge(tab) {
    const badge = tab.properties?.badge;
    if (typeof badge === "number" && Number.isInteger(badge)) {
        return badge > 99 ? "99+" : String(badge);
    }
    if (typeof badge === "string") {
        return badge.length > 0 ? badge : null;
    }
    return null;
}
