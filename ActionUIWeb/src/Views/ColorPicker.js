// ColorPicker.js — ColorPicker element.
// Web analog of ActionUI/Views/ColorPicker.swift (and ActionUIAndroid Views/ColorPicker.kt).
//
// A color well, rendered as a native <input type="color">. Apple's valueType is
// Color; the web has no Color token, so valueType is "string" and the value is a
// "#rrggbb" hex (the native input's own format). A host reads/writes it with
// get/setString(id).
//
// Properties (mirroring ColorPicker.swift):
//   title          leading label; defaults to empty.
//   selectedColor  initial color (hex "#rgb"/"#rrggbb", or a CSS/named color
//                  resolved to hex via a canvas when available); defaults to the
//                  native control's #000000 (the web has no Color.clear).
//   actionID       dispatched on user color change (the native `input`);
//                  programmatic setString is silent (the Apple binding setter only
//                  fires on UI interaction).

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

register("ColorPicker", {
    valueType: "string",

    // Mirrors ColorPicker.swift validateProperties (the dynamic Swift type name in
    // each message is replaced by the JS typeof).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log(`Invalid type for ColorPicker title: expected String, got ${typeof validated.title}, ignoring`, "warning");
            delete validated.title;
        }
        if (validated.selectedColor !== undefined && typeof validated.selectedColor !== "string") {
            logger.log(`Invalid type for ColorPicker selectedColor: expected String, got ${typeof validated.selectedColor}, ignoring`, "warning");
            delete validated.selectedColor;
        }
        if (validated.actionID !== undefined && typeof validated.actionID !== "string") {
            logger.log(`Invalid type for ColorPicker actionID: expected String, got ${typeof validated.actionID}, ignoring`, "warning");
            delete validated.actionID;
        }

        return validated;
    },

    // Seeds the resolved hex when selectedColor is given; absent/unresolvable ⇒
    // undefined (no seed), and the native control shows its default #000000.
    initialValue: (element, properties) => toHexColor(properties.selectedColor) || undefined,

    buildView: (element, properties, ctx) => {
        const title = properties.title ?? "";
        const initial = toHexColor(properties.selectedColor);

        const input = document.createElement("input");
        input.type = "color";
        input.className = "aui-colorpicker";
        if (initial) input.value = initial;

        const dispatchChange = () => {
            if (typeof properties.actionID === "string") {
                ctx.model.dispatchAction(properties.actionID, element.id);
            }
        };

        markHandlesAction(input);
        // `input` fires live as the color changes (the Apple binding setter).
        input.addEventListener("input", dispatchChange);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => input.value,
                setValue: (value) => { // programmatic: silent
                    const hex = toHexColor(value);
                    if (hex) input.value = hex;
                },
            });
        }

        // Leading label, shown only when a title is present (default is empty),
        // reusing the shared labeled-field layout.
        if (title) {
            const wrapper = document.createElement("label");
            wrapper.className = "aui-labeled-field";
            const label = document.createElement("span");
            label.className = "aui-field-label";
            label.textContent = title;
            wrapper.append(label, input);
            return wrapper;
        }
        return input;
    },
});

// Normalizes a CSS color string to the <input type="color"> format "#rrggbb".
// Handles #rgb / #rrggbb directly; for named/other CSS colors it uses a canvas to
// resolve (browser only) and returns "" when unavailable or unresolvable.
function toHexColor(value) {
    if (typeof value !== "string") return "";
    const v = value.trim();
    if (/^#[0-9a-f]{6}$/i.test(v)) return v.toLowerCase();
    if (/^#[0-9a-f]{3}$/i.test(v)) {
        return "#" + v.slice(1).split("").map((c) => c + c).join("").toLowerCase();
    }
    if (v === "") return "";
    if (typeof document !== "undefined" && typeof document.createElement === "function") {
        try {
            const context = document.createElement("canvas").getContext?.("2d");
            if (context) {
                context.fillStyle = "#000000";
                context.fillStyle = v; // the canvas normalizes any valid CSS color
                if (/^#[0-9a-f]{6}$/i.test(context.fillStyle)) return context.fillStyle.toLowerCase();
            }
        } catch {
            /* fall through to "" */
        }
    }
    return "";
}
