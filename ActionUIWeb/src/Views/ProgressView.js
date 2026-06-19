// ProgressView.js — ProgressView element.
// Web analog of ActionUI/Views/ProgressView.swift (and ActionUIAndroid Views/ProgressView.kt).
//
// A progress indicator, rendered as a native <progress>. It is **determinate**
// (a filled bar) when a valid value is supplied and value <= total, otherwise
// **indeterminate** (the browser's animated bar — the web counterpart of the
// SwiftUI/Material spinner). valueType is "double": a host reads/writes the
// progress with get/setDouble(id); setting the value to null reverts to
// indeterminate, mirroring Apple's states["progress"] = nil.
//
// Properties (mirroring ProgressView.swift):
//   value    current progress, 0.0…total (Double). Omit (or supply an invalid /
//            out-of-range value) for an indeterminate indicator.
//   total    maximum (positive Double); defaults to 1.0 when value is present.
//   title    optional label shown above the indicator.
//   actionID dispatched on tap/click (like Button), with no context.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

register("ProgressView", {
    valueType: "double",

    // Mirrors ProgressView.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // value: a non-negative number, else dropped (⇒ indeterminate).
        if (validated.value !== undefined && !(typeof validated.value === "number" && validated.value >= 0.0)) {
            logger.log("ProgressView value must be a non-negative Double; defaulting to nil", "warning");
            delete validated.value;
        }

        // total: a positive number, else dropped.
        if (validated.total !== undefined && !(typeof validated.total === "number" && validated.total > 0.0)) {
            logger.log("ProgressView total must be a positive Double; defaulting to nil", "warning");
            delete validated.total;
        }

        // title: must be a String, else dropped.
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("ProgressView title must be a String; defaulting to nil", "warning");
            delete validated.title;
        }

        return validated;
    },

    // Seeds the determinate value; absent ⇒ undefined ⇒ no seed (indeterminate).
    initialValue: (element, properties) => properties.value,

    buildView: (element, properties, ctx) => {
        // total defaults to 1.0 when a value is present — the documented behavior,
        // matching the Android port. (Apple's buildView has a latent quirk, noted
        // by its own TODO, where an absent total falls through to indeterminate;
        // we follow the documented/Android semantics. See Web_Porting_Notes.md.)
        const total = properties.total ?? 1.0;
        let current = (typeof properties.value === "number") ? properties.value : null;

        const isDeterminate = (value) => value !== null && Number.isFinite(value) && value >= 0 && value <= total;

        const bar = document.createElement("progress");
        bar.className = "aui-progress-bar";
        bar.max = total;
        // A <progress> with no value attribute renders as indeterminate; setting
        // .value makes it determinate.
        const renderValue = () => {
            if (isDeterminate(current)) {
                bar.value = current;
            } else {
                current = null;
                bar.removeAttribute("value");
            }
        };
        renderValue();

        // A title wraps the bar in a column, matching ProgressView(title, …) and
        // the Android Column; otherwise the bare bar is the root.
        let root = bar;
        if (properties.title) {
            root = document.createElement("div");
            root.className = "aui-progress";
            const label = document.createElement("span");
            label.className = "aui-progress-title";
            label.textContent = properties.title;
            root.append(label, bar);
        }

        // actionID fires on tap/click, like Button (no context), on the root.
        if (typeof properties.actionID === "string") {
            markHandlesAction(root);
            root.addEventListener("click", () => {
                ctx.model.dispatchAction(properties.actionID, element.id);
            });
        }

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                // null when indeterminate (the host can branch on it); a number
                // otherwise.
                getValue: () => (isDeterminate(current) ? current : null),
                setValue: (value) => {
                    // A valid number ⇒ determinate; null/invalid ⇒ indeterminate
                    // (the web analog of setting states["progress"] = nil).
                    const n = Number(value);
                    current = (value !== null && value !== undefined && Number.isFinite(n)) ? n : null;
                    renderValue();
                },
            });
        }
        return root;
    },
});
