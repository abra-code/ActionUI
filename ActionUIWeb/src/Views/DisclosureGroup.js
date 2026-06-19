// DisclosureGroup.js — DisclosureGroup element.
// Web analog of ActionUI/Views/DisclosureGroup.swift (and ActionUIAndroid
// Views/DisclosureGroup.kt).
//
// An expand/collapse container with a clickable title header, rendered as the
// native <details>/<summary> pair. The expanded flag is **observable state**
// (not a value): it lives under the "isExpanded" key and is read/driven through
// the state side of the bridge (win.getState / win.setState) — this is the
// first web element to use it, as DisclosureGroup was on Android. One visual
// divergence: the native disclosure marker leads the title, whereas SwiftUI's
// chevron trails it (see Web_Porting_Notes.md). The template/setElementRows
// data-driven mode is deferred with the insertion API — only `children` renders.
//
// Properties: title (String header label, defaults to ""), isExpanded (Boolean
// initial state, defaults to false), valueChangeActionID (dispatched on each
// user expand/collapse; programmatic setState changes are silent, as on Apple
// where only the user-interaction binding setter dispatches).

import { register } from "../Common/ActionUIRegistry.js";
import { StackAxis } from "../Common/StackAxis.js";

register("DisclosureGroup", {
    valueType: "none",

    // Mirrors DisclosureGroup.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("DisclosureGroup 'title' must be String; setting to nil", "warning");
            delete validated.title;
        }
        if (validated.isExpanded !== undefined && typeof validated.isExpanded !== "boolean") {
            logger.log("DisclosureGroup 'isExpanded' must be Bool; setting to nil", "warning");
            delete validated.isExpanded;
        }
        return validated;
    },

    // Seeds states["isExpanded"], mirroring the Apple/Android initialStates.
    initialStates: (element, properties) => ({ isExpanded: properties.isExpanded ?? false }),

    buildView: (element, properties, ctx) => {
        const details = document.createElement("details");
        details.className = "aui-disclosure";
        details.open = properties.isExpanded ?? false;

        const summary = document.createElement("summary");
        summary.className = "aui-disclosure-title";
        summary.textContent = properties.title ?? "";
        details.appendChild(summary);

        const content = document.createElement("div");
        content.className = "aui-stack aui-vstack aui-disclosure-content";
        content.dataset.auiAxis = StackAxis.Vertical;
        for (const child of element.children()) {
            content.appendChild(ctx.build(child));
        }
        details.appendChild(content);

        // knownOpen tracks every change this code made (initial + setState), so
        // the toggle handler — which also fires, async, for those programmatic
        // .open writes — dispatches only for user expand/collapse.
        let knownOpen = details.open;
        details.addEventListener("toggle", () => {
            if (details.open === knownOpen) return; // programmatic; already recorded
            knownOpen = details.open;
            if (typeof properties.valueChangeActionID === "string") {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id);
            }
        });

        if (element.id > 0) {
            ctx.model.bindState(element.id, {
                getState: (key) => (key === "isExpanded" ? details.open : undefined),
                setState: (key, value) => {
                    if (key !== "isExpanded") return; // unowned keys stay in the fallback map
                    knownOpen = Boolean(value);
                    details.open = knownOpen;
                },
            });
        }
        return details;
    },
});
