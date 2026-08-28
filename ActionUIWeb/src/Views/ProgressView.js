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
//   progressViewStyle  "automatic" | "linear" | "circular". The web has only one
//            native indicator, <progress>, and it is LINEAR in both the
//            determinate and the indeterminate state - so this port already
//            renders what "linear" asks for and the property is accepted here
//            for portability. "circular" has no native analog and is not ported:
//            it warns and stays linear, the same warn-and-fall-back the Picker
//            and Toggle ports use for a style a platform cannot honor.
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

        // progressViewStyle: one of the three names, else dropped.
        if (validated.progressViewStyle !== undefined) {
            const validStyles = ["automatic", "linear", "circular"];
            if (typeof validated.progressViewStyle !== "string") {
                logger.log("ProgressView progressViewStyle must be a String; defaulting to nil", "warning");
                delete validated.progressViewStyle;
            } else if (!validStyles.includes(validated.progressViewStyle)) {
                logger.log(`ProgressView progressViewStyle '${validated.progressViewStyle}' must be one of ${validStyles}; defaulting to nil`, "warning");
                delete validated.progressViewStyle;
            }
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

        // <progress> is linear in both states, so "linear" and "automatic" are
        // already what this builds. "circular" has no native analog on the web;
        // warn and stay linear rather than silently rendering something the JSON
        // did not ask for. The style is recorded on the element either way, as
        // Picker does with data-aui-picker-style, so a stylesheet can hook it.
        const style = properties.progressViewStyle;
        if (style === "circular") {
            ctx.logger.log("ProgressView progressViewStyle 'circular' is not ported on the web; using the linear indicator", "warning");
        }

        const bar = document.createElement("progress");
        bar.className = "aui-progress-bar";
        if (typeof style === "string") {
            bar.dataset.auiProgressViewStyle = style;
        }
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
