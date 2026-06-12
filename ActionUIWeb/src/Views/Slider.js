// Slider.js — Slider element.
// Web analog of ActionUI/Views/Slider.swift (and ActionUIAndroid Views/Slider.kt).
//
// A continuous (or stepped) value selector along a linear range, rendered as an
// <input type="range">. The first Double-valued control on the web state bridge:
// valueType is "double", so a host reads the position with get/setDouble(id) and
// the thumb tracks it.
//
// Properties (mirroring Slider.swift):
//   value  initial position (Double, defaults to 0.0).
//   range  { min, max } (defaults to 0.0…1.0; min <= max).
//   step   increment; absent or non-positive ⇒ continuous (input step="any").
//          Clamped so it never exceeds the range size, matching the validator.
//   valueChangeActionID  dispatched on every change (the analog of the Apple
//          binding's `set` closure), including programmatic setElementValue.

import { register } from "../Common/ActionUIRegistry.js";
import { markHandlesAction } from "../Common/ModifierResolver.js";

const DEFAULT_RANGE = { min: 0.0, max: 1.0 };

register("Slider", {
    valueType: "double",

    // Mirrors Slider.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // value: a non-number (but present) defaults to 0.0; absent ⇒ 0.0.
        if (typeof validated.value !== "number") {
            if (validated.value !== undefined) {
                logger.log("Slider value must be a number; defaulting to 0.0", "warning");
            }
            validated.value = 0.0;
        }

        // range: a dictionary with numeric min/max and min <= max, else 0.0…1.0.
        if (isPlainObject(validated.range)) {
            const { min, max } = validated.range;
            if (typeof min === "number" && typeof max === "number" && min <= max) {
                validated.range = { min, max };
            } else {
                logger.log("Slider range must have valid min/max numbers with min <= max; defaulting to 0.0...1.0", "warning");
                validated.range = { ...DEFAULT_RANGE };
            }
        } else if (validated.range !== undefined) {
            logger.log("Slider range must be a dictionary with min/max numbers; defaulting to 0.0...1.0", "warning");
            validated.range = { ...DEFAULT_RANGE };
        }

        // step: a positive number, clamped to the range size; a valid range is
        // required for a step (matching "range becomes required if you specify
        // step"), else it defaults to 1.0.
        if (typeof validated.step === "number" && validated.step > 0) {
            if (isPlainObject(validated.range)
                && typeof validated.range.min === "number" && typeof validated.range.max === "number") {
                const rangeSize = validated.range.max - validated.range.min;
                if (validated.step > rangeSize) {
                    logger.log(`Slider step must not exceed range (max - min); clamping to ${formatDouble(rangeSize)}`, "warning");
                    validated.step = rangeSize;
                }
            } else {
                logger.log("Slider step requires a valid range; defaulting to 1.0", "warning");
                validated.step = 1.0;
            }
        } else if (validated.step !== undefined) {
            logger.log("Slider step must be a positive number; defaulting to 1.0", "warning");
            validated.step = 1.0;
        }

        return validated;
    },

    initialValue: (element, properties) => properties.value ?? 0.0,

    buildView: (element, properties, ctx) => {
        const min = properties.range?.min ?? DEFAULT_RANGE.min;
        const max = properties.range?.max ?? DEFAULT_RANGE.max;
        const initial = properties.value ?? 0.0;

        const input = document.createElement("input");
        input.type = "range";
        input.className = "aui-slider";
        input.min = String(min);
        input.max = String(max);
        // A positive step snaps; otherwise "any" keeps the slide continuous (the
        // browser default is 1, which would quantize a 0…1 range to its endpoints).
        input.step = (typeof properties.step === "number" && properties.step > 0)
            ? String(properties.step) : "any";
        input.value = String(clamp(initial, min, max));

        const dispatchValueChange = () => {
            if (typeof properties.valueChangeActionID === "string") {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id);
            }
        };

        markHandlesAction(input);
        // `input` fires on every position change during a drag (SwiftUI's binding
        // set); `change` would only fire on release.
        input.addEventListener("input", dispatchValueChange);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => Number(input.value),
                setValue: (value) => {
                    const n = Number(value);
                    input.value = String(clamp(Number.isFinite(n) ? n : initial, min, max));
                    dispatchValueChange();
                },
            });
        }
        return input;
    },
});

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

// Formats a number the way Swift/Kotlin interpolate a Double, so the warning text
// matches the reference platforms (an integer-valued Double prints "10.0", not
// "10"). Non-integers use JS's shortest round-trip form, as the others do.
function formatDouble(n) {
    return Number.isInteger(n) ? n.toFixed(1) : String(n);
}

function clamp(value, min, max) {
    return Math.min(Math.max(value, min), max);
}
